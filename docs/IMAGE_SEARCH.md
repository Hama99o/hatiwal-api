# Search by image (1.2.0)

A buyer taps 📷 in the search bar, takes or picks ONE photo, and gets the
listings whose photos look like it. Everything runs on our own server: no photo,
vector or search ever goes to Hugging Face, Google or anyone else.

Background and the feasibility numbers: `docs/IMAGE_SEARCH_TEST_2026-10-29.md`
in the workspace root. Legend below: **[measured]** = run and read,
**[inferred]** = estimate.

## 1. Pieces

| Piece | File |
|---|---|
| Model + preprocessing | `app/services/image_search/embedder.rb` |
| On/off (model present, kill switch) | `app/services/image_search.rb` |
| One vector per listing photo | `app/models/listing_image_embedding.rb`, migration `20261029200000` |
| Nearest-photo lookup (the pgvector seam) | `app/services/image_search/ruby_cosine_index.rb` |
| Ranking: min score + category boost | `app/services/image_search/search.rb` |
| Store one photo's vector | `app/services/image_search/indexer.rb` |
| New photo → job | `config/initializers/image_search.rb`, `app/jobs/embed_listing_image_job.rb` |
| Old photos | `app/jobs/backfill_image_embeddings_job.rb`, `bin/rails image_search:backfill` / `:stats` |
| Endpoint | `Api::V1::ListingsController#image_search`, `ListingPolicy#image_search?` |
| Feature flag for the apps | `GET /app_config` → `features.image_search` |
| Model download (build time only) | `bin/fetch-image-model`, `Dockerfile` |

## 2. The model

- `Xenova/clip-vit-base-patch32`, image half only, quantized: `onnx/vision_model_quantized.onnx`
  (89 MB, MIT), Hugging Face revision `6b7c523703ae26e39be4b03774966f8571c7f523`, sha256
  `583fd111…9839299`. 512-number vectors.
- Run with the `onnxruntime` gem. The feasibility test used `informers`; we dropped it: its
  preprocessing is pure Ruby (0.16 s of each photo), libvips does the same steps in 0.05 s,
  and the vectors are identical (cosine 1.0000 on the seed photos) **[measured]**. One gem
  (`onnxruntime` + `ffi`) instead of four (`informers`, `tokenizers`, `rb_sys`,
  `rake-compiler-dock`).
- Preprocessing (libvips): shrink-on-load to 224 px on the short side, centre crop 224×224,
  EXIF rotation, alpha flattened on white, greyscale → sRGB, CLIP mean/std. A truncated file
  is refused (`fail_on=truncated`), and so is a blank frame (pixel std-dev < 6: a covered
  lens), which answers an empty result instead of "everything on a white background".
- **Never downloaded at runtime.** `bin/fetch-image-model` downloads the pinned file and
  checks its sha256; the Dockerfile runs it at build time (a bad download fails the build).
  The file lives in `vendor/image_models/` (gitignored and dockerignored, so a dev copy is
  never shipped by accident). `IMAGE_SEARCH_MODEL_DIR` overrides the folder.
- `MODEL_VERSION` (`clip-vit-b32-q8@6b7c523`) is stored with every vector. Change it when the
  model, revision or preprocessing changes, then run the backfill: the search only compares
  vectors of today's version.

## 3. Storage (no pgvector in 1.2.0)

Production runs plain `postgres:16`; switching the image to pgvector means a DB restart, not
worth it for 1.2.0. So `listing_image_embeddings` holds, per listing photo: `listing_id`,
`attachment_id`, `model_version`, and the vector as 512 little-endian float32 in a `bytea`
(2 KB). Both foreign keys `ON DELETE CASCADE`: a removed photo or deleted listing takes its
rows with it. Unique on `(attachment_id, model_version)`.

The search reads the vectors of the browsable listings and does the dot product in Ruby
(`RubyCosineIndex`, exact). **Later**: add a `vector(512)` column (pgvector + `neighbor`),
fill it from this one, and replace `RubyCosineIndex.best_scores` with
`nearest_neighbors(:embedding, v, distance: "cosine")` grouped by listing. `Search` does not
change.

## 4. Jobs

- `after_create_commit` on an Active Storage attachment with `record_type: "Listing"` and
  `name: "images"` enqueues `EmbedListingImageJob` (queue `image_embeddings`). Only listing
  photos: never avatars, chat photos, shop media or verification files (specs prove avatars).
- Both jobs carry `limits_concurrency to: 1` with one shared key: one embedding at a time in
  the whole app, and the waiting ones are *blocked* jobs that hold no worker thread, so chat
  pushes are never stuck behind a backfill.
- A photo the decoder cannot read is logged and dropped (no retry loop); a file not yet in
  storage is retried 5× (30 s apart).
- `BackfillImageEmbeddingsJob`: 100 photos per run, then enqueues the next batch after the
  last attachment id, so a broken photo is skipped, not retried forever.
  `bin/rails image_search:backfill` runs every batch inline and prints progress;
  `bin/rails image_search:stats` prints the coverage.
- Off in the test environment (`config.x.image_search_enabled = false`), so the rest of the
  suite enqueues nothing new; this feature's specs switch it on with `:image_search`.

## 5. Endpoint

```
POST /api/v1/listings/image_search          multipart/form-data, public (guest or signed in)
  image          one photo: jpeg/png/webp/gif/heic/heif/avif, by its BYTES (Marcel), ≤ 10 MB
  category_id    optional, the category and its subcategories (as the feed)
  location       optional free text (as the feed without coordinates)
  page[number], page[size]   like the feed
→ 200 { listings: [...ListingSerializer :list...], meta: { pagination } }   best match first
→ 422 { error, code }  code: image_missing | image_too_large | invalid_image
→ 429 rate_limited (Retry-After)    30 / 10 min per user (a guest: per IP), 120 / 10 min per IP
→ 503 { code: image_search_unavailable }   no model on this server (or IMAGE_SEARCH_ENABLED=0)
```

- The photo is read into memory, embedded and dropped: never attached, saved or logged; its
  multipart tempfile is deleted at once. A spec proves no blob or attachment is created.
- Scope = the feed's: `policy_scope(Listing.browsable).not_hidden_for(current_user)` — never
  draft, sold, expired, removed, closed-shop, banned-seller or blocked-pair listings.
- At most `Search::MAX_RESULTS` (60) results. Each page re-sends the photo, so the apps ask for
  one page of 60.
- The apps show the 📷 button only when `GET /app_config` says `features.image_search: true`,
  so an API without the model (or with the kill switch) never offers it.

## 6. Ranking and tuning

Score = the best cosine similarity over a listing's photos (every photo is indexed). Then:

- **Minimum score 0.62**: below it a listing is not shown.
- **Same-category boost +0.03**: the top 10 matches vote for a top-level category, weighted by
  score; when one holds ≥ 50% of the votes, its listings get +0.03.

Tuned on 2026-10-29 **[measured]** with `tune.rb` (kept with its output in hatiwal-mobile
`docs/qa-1.2.0/image-search/api/`), on:
the 44 public production photos of the 18 live listings (the same set as the feasibility
test), leave-one-out — every photo of a listing with 2+ photos is a query (35 queries), the
index is every OTHER photo — plus 15 negatives: 10 seed photos of things production does not
sell (sofas, chairs, wardrobe, motorcycles, camera, laptop) and 5 synthetic ones (white,
black, noise, gradient, a text receipt).

| Min score | hit@1 | hit@5 | MRR | true match kept | negatives that still get results | results per search |
|---|---|---|---|---|---|---|
| none | 29/35 | 34/35 | 0.89 | 35/35 | 15/15 | 18.0 |
| 0.60 | 29/35 | 34/35 | 0.89 | 35/35 | 11/15 | 5.4 |
| **0.62** | **29/35** | **34/35** | **0.89** | **35/35** | **9/15** | **4.4** |
| 0.65 | 29/35 | 32/35 | 0.86 | 32/35 | 8/15 | 3.2 |
| 0.70 | 29/35 | 32/35 | 0.86 | 32/35 | 6/15 | 2.0 |

- Why 0.62: the highest cut that still keeps every true match (the weakest are 0.63: the back
  label of a cream tube). It halves the results per search against "no cut-off".
- What a cut-off cannot do: true matches go down to 0.63 while a wrong listing can score 0.86
  (CLIP sees "an iPhone", not the model), and photos of things we do not sell score 0.57–0.72.
  A threshold only removes the obvious junk. Most "negatives" that still get results are
  near-misses a buyer may accept (a motorcycle → the bicycles; a camera/laptop → the phones).
- Blank frames scored 0.73 (white) / 0.73 (black) / 0.80 (gradient) against products shot on
  white, which is why the plain-photo guard exists (§2).
- Centring the vectors (subtracting the index mean) was tried: it separates a bit better at
  mid thresholds but drops true matches, and needs a mean that moves with the index. Not used.
- **The category boost changed nothing on this data** (hit@1, hit@5, MRR identical for
  boost 0 / 0.02 / 0.03 / 0.05): with 1–4 listings per category there is nothing to reorder.
  It is kept small (0.03, a tenth of the right/wrong gap) as the design asks; it is NOT
  validated. Re-run the tuning when production has a few hundred listings.

## 7. Speed **[measured, dev box, 16 threads, `IMAGE_SEARCH_THREADS=2`]**

| | |
|---|---|
| Model load (first photo in a process) | 1.15 s |
| Embed one photo (seed JPEG) | 0.37 s mean, 0.45 s max (prod photos: 0.28 s mean) |
| Search over 5 000 vectors (42 listings) | 0.62 s mean, 0.71 s max |
| of which: SQL + reading 10 MB of vectors | 0.27 s |
| Search over today's prod size (44 photos) **[inferred]** | ~10 ms |

So one search request ≈ embed + search ≈ 0.4 s today, ≈ 1 s at 5 000 photos, on this box.
On the 4-vCore VPS **[inferred]** ×1.5–2. The embed and the Ruby dot product hold Ruby's GVL
(onnxruntime's run is not GVL-free), so a search briefly blocks Puma's other 2 threads; the
rate limit bounds it. **Move to pgvector when photos pass ~3 000.**

## 8. RAM **[measured, `bin/rails runner`, development]**

| | RSS |
|---|---|
| Rails booted | 141 MB |
| Model loaded + first embed | 386 MB (+245 MB) |
| After 10 embeds | 446 MB |
| After 10 searches over 5 000 vectors | 579 MB (peak 580) |

Expected extra RAM in production: **+0.3 GB per process that loads the model** (only on
first use), up to ~+0.45 GB with 5 000 vectors searched. Two processes can load it: the Puma
web process (first search) and the Solid Queue worker forked by `SOLID_QUEUE_IN_PUMA` (first
photo). Worst case **≈ +0.75–0.9 GB** on the 8 GB VPS that uses ~0.75 GB today **[inferred]**.

## 9. Deploying (for the release session)

1. The migration runs with the deploy (`db:prepare` in the entrypoint): one new table.
2. The image grows by the model (89 MB) + onnxruntime (~20 MB).
3. After the deploy, embed the existing photos once:
   `bin/kamal app exec 'bin/rails image_search:backfill'` (prod: 44 photos ≈ 15 s
   **[inferred]**; it runs in that one-off container, not in Puma). Check with
   `bin/rails image_search:stats`.
   Then warm sell with a photo's category vectors (docs/SELL_WITH_PHOTO.md §4):
   `bin/kamal app exec 'bin/rails category_suggestion:warm'`.
4. Kill switch without a code change: set `IMAGE_SEARCH_ENABLED=0` in the env (and reboot the app) → `/app_config` says false,
   the apps hide 📷, the endpoint answers 503, no new embed jobs.
