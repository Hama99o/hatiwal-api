# Sell with a photo — category suggestion (1.2.1)

Board card 377 (IDEA-3). Design and acceptance criteria: hatiwal-mobile
`docs/design/SELL_WITH_PHOTO.md`. Measurements: hatiwal-mobile
`docs/qa-1.2.1/sell-photo/measure/`.

When a seller adds the **first photo of a new listing**, the apps ask the API which category the
photo shows. The answer is a category **id** and a confidence, or nothing. The apps show it as a
chip the seller can accept or dismiss. They never pick a category on their own, and never
replace one the seller already chose.

**Out of scope for 1.2.1:** title suggestion (owner, 2026-10-30: too hard to do well in ps/fa).

## 1. Model

Zero-shot CLIP: the same model as search by image (`Xenova/clip-vit-base-patch32`, revision
`6b7c523`), with its **text** half added.

| File (revision 6b7c523) | Size | sha256 |
|---|---|---|
| `onnx/vision_model_quantized.onnx` (already used by search by image) | 89 MB | `583fd111…` |
| `onnx/text_model_quantized.onnx` | 64.5 MB | `73baab85…` |
| `vocab.json` | 0.9 MB | `5047b556…` |
| `merges.txt` | 0.5 MB | `9fd691f7…` |

`bin/fetch-image-model` downloads and checks all four at Docker build time. The full hashes are in
the script. The Dockerfile is unchanged: it already runs the script.

- **Prompts:** `config/sell_photo/prompts.yml` holds English phrases per category slug
  ("a photo of a mobile phone", …). These are only ever compared with photos. They are never
  shown to anyone: the apps show the category's own `name_ps` / `name_fa` / `name_en`.
  - The phrases of one category are averaged (prompt ensembling).
  - Only slugs listed in the file can be suggested. Property, Stays, Jobs, Services and Other
    are left out on purpose, because a photo cannot tell them apart.
- **Tokenizer:** `ImageSearch::ClipTokenizer` is CLIP's byte-level BPE in plain Ruby, from the
  revision's own `vocab.json` + `merges.txt`. It gives the same ids as Hugging Face `tokenizers`
  on all 141 phrases we use, accents included (the spec holds reference ids). It is not a gem, so there is no
  native extension and no Gemfile change.
- **Category vectors:** one per slug of the prompts file (57), embedded once per process on
  the first suggestion, then kept (a few hundred KB).
  - The text model is loaded only for that warm-up and dropped right after, so it costs no
    lasting RAM.
  - The vectors depend only on the model and the prompts file, so they are also stored in
    `Rails.cache` under the model version + the file's sha256. Other processes skip the ~6 s
    warm-up.
- **Scoring:**
  1. Embed the photo (`ImageSearch::Embedder`, identical to search by image).
  2. Take the cosine with every category vector, × 100 (CLIP's logit scale).
  3. Softmax over **every slug of the prompts file**, whatever the database holds.
  4. The best slug is suggested only if its probability is **≥ 0.40** and its category is
     active. Otherwise the answer is 204, "no suggestion".

  A switched-off category still takes its share. Its photos are then not offered rather than
  handed to the last categories left: with only one or two candidates, a softmax gives any
  photo 50–100%. The spec caught this.
- **Cost:** one photo embed (0.3–0.5 s of CPU, the same as one image search) plus 57 dot
  products. RAM: the image model is shared with search by image (+0.3 GB, already paid in the
  web process). The text model is held only during the warm-up (to be measured with
  `bin/rails runner`).

### Zero-shot vs a vote of similar listings [measured 2026-10-30]

Precision at threshold 0.40 = the share of shown suggestions that are the right subcategory.

| Test set | Zero-shot (v2 prompts) | kNN vote over existing listings |
|---|---|---|
| 170 held-out Commons photos, 42 categories, labels checked by eye | **0.94** (98/170 get a chip); top-level category right 0.99 | n/a (none of them are listings) |
| 25 CC0 seed photos | 1.00 (19/25) | n/a |
| 44 public production photos, seller's own labels | 0.64 (25/44), see below | 0.29 (28/44), best 0.40 |
| …first photo of each of the 18 production listings | 0.78 (9/18) | — |

**Zero-shot is chosen.** The kNN vote cannot work yet: production has 18 live listings, and most
categories have one listing or none, so a photo's "nearest" listings are mostly from other
categories. Re-measure the combination (agreement → boost) when production has a few hundred
listings. `ImageSearch::RubyCosineIndex` already gives the neighbours.

The 9 production misses at ≥ 0.40, looked at photo by photo:
- **7 are one listing:** an air-freshener spray the seller filed under "Other", suggested as
  Fragrances (6) and Haircare (1). "Other" can never be suggested.
- **1 is label noise:** a "Jacket" listing whose photo is a phone → Phones.
- **1 is a real mistake:** a feather duster → Haircare.

The v2 prompts added generic packaging, tool and phone-screen phrases. They were written
**after** looking at the production misses, so production is a tuning set, not a test. The
held-out set is the honest number, and it moved from 0.94 → 0.94 (no overfit cost).

## 2. Endpoint

`POST /api/v1/my/listings/category_suggestion`, multipart, one `image`.

- **Signed in only.** Throttled at 30 / 10 min per user and 120 / 10 min per IP, the same as
  image search.
- **The photo is never stored, logged or attached.** It gets the same size cap and the same
  file-type check as a listing photo (Marcel on the leading bytes).
- **Responses:**
  - `200 {"category_id": 16, "parent_id": 1, "confidence": 0.62}`
  - `204` when unsure, when the photo is plain or blank, or when no suggestible category is
    active.
  - `422` for `image_missing` / `invalid_image` / `image_too_large`.
  - `503` for `category_suggestion_unavailable` (no model, or the kill switch is on).
- **No title**, and no text in any language: the apps render the category name in the seller's
  language from the categories they already have.
- **Feature flag:** `GET /app_config` gets `features.category_suggestion`. It is true when both
  model halves are on disk, unless `CATEGORY_SUGGESTION_ENABLED=0`. The apps only ever call the
  endpoint when the flag is true.

## 3. Outcome log (for tuning after release)

`POST /api/v1/my/listings/category_suggestion/outcome` takes
`{outcome: accepted | dismissed | replaced, category_id, confidence}` and answers 204.
`replaced` means the seller picked another category while the chip was shown. It is limited to
60 per 10 min per user.

The server writes one log line per answer and per outcome. The lines carry ids and numbers
only: no photo, no user, nothing the seller wrote.

```
category_suggestion event=suggested category_id=16 confidence=0.62
category_suggestion event=none
category_suggestion event=accepted category_id=16 confidence=0.62
category_suggestion event=dismissed category_id=16 confidence=0.48
category_suggestion event=replaced category_id=16 confidence=0.41
```

How to read them after release:
- **Real precision:** accepted ÷ (accepted + replaced). Dismissals are ambiguous: the seller
  may also just prefer to pick the category themselves.
- **Coverage:** suggested ÷ (suggested + none).
- **Re-tuning:** split by confidence band to move `MIN_CONFIDENCE`.
- **Command:** `bin/kms app logs` piped into `grep category_suggestion`, then count by `event`.

## 4. Deploying (for the release session)

1. The image grows by the text model (64.5 MB) and its tokenizer files (1.4 MB):
   `bin/fetch-image-model` fetches them at build time, beside the image model.
2. After the deploy, build the category vectors once into the shared cache:
   `bin/kamal app exec 'bin/rails category_suggestion:warm'` (~6 s in that one-off container).
   - Production's cache is `solid_cache_store` (the `cache` database), which every Puma
     worker and every job container shares. So this rake task is the right place, and no boot
     hook is needed: a boot hook would add the ~6 s to every process, job workers included.
   - Without the task, the first suggestion after a deploy takes ~6 s once (measured 5.8 s on
     the dev box), then ~0.4 s.
   - The cache key carries the model version and the prompts file's sha256, so an edited
     prompts file needs the task again.
   - The entry is ~250 KB under a 256 MB cap. An eviction only means one more slow request.
3. Kill switch without a code change: `CATEGORY_SUGGESTION_ENABLED=0` (and reboot the app).
   `/app_config` then says false, the apps never ask, and the endpoint answers 503. Search by
   image's own switch (`IMAGE_SEARCH_ENABLED=0`) turns this off too.
