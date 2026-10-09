# privacy-b — no owner id in what a buyer sees of a shop

**DECIDED by the owner (2026-10-09): ships in 1.1.7.** Rebased onto the `release-1.1.7` heads
(2026-10-09 evening, hatiwal-d0); still on SIDE branches until it is merged into 1.1.7.

| Repo | Branch | Head | Based on |
|---|---|---|---|
| api | `privacy-b` (worktree `.worktrees/api-privacy-b`) | `1e237e5` + this doc | api `release-1.1.7` `de8da01` |
| web | `privacy-b-web` (`.worktrees/web-privacy-b`) | `c9dc5ea` | web `release-1.1.7` `4710af7` |
| mobile | `privacy-b-mobile` (`.worktrees/mobile-privacy-b`) | `32c574bc` | mobile `release-1.1.7` `4f9a463d` |

Each is rebased on its release head and merges as a fast-forward of one commit.

## Why

The 1.1.6 privacy text promises buyers see the shop, "never your personal name, photo" and
"never the member who posted". Already fixed IN the release tonight:

- the public shop endpoint named the owner (api `9d153d0`);
- a message written as the shop carried the member's user id (api `c714771`).

What remains, and what this branch fixes: the shop's face in a listing (`seller`) and in a chat
(`seller` / `other_participant`) carries the **owner's user id**, and
`GET /users/:id/public_profile` is guest-readable — so any buyer can turn that id into the owner's
name and photo.

## What changes

- **API** — a shop's face carries `id: null` + `shop_id` for anyone not on the shop's team. The
  team keeps the owner id (its "is this mine" checks).
- **Legacy gate** — clients older than **1.1.7** keep the owner id (`ShopFace::NEW_CLIENT_VERSION`,
  moved from 1.1.6 to 1.1.7 on 2026-10-09: the shipped 1.1.6 store build has none of privacy-b's
  client code and must keep working). A client is "new" only with `X-App-Version` ≥ 1.1.7 or
  `X-App-Platform: web`. Store builds before 2026-10-01 send no version at all → legacy.
- **Block / report a shop by its id** — `POST/DELETE /shops/:id/block` blocks the owner underneath
  (every existing block check unchanged); `GET /blocks` lists the SHOP to new clients. A shop can be
  reported (`reportable_type: "Shop"`), never by its own team. Admin: the report page names the
  shop and its owner and can warn the owner.
- **Web** — sends `X-App-Platform: web`; shop faces link to the shop page (never `/sellers/null`);
  "is this mine" by shop membership; block / unblock / report the shop; the blocked list shows shops.
- **Mobile** — the same: shop faces route to the shop page, "is this mine" by membership, block /
  unblock / report the shop (also today, while the owner id still arrives), blocked list shows shops.

## Behaviour changes to know

1. ~~Managers and staff get the seller tools~~ — no longer part of this branch: it was a 1.1.6 bug
   in its own right and is fixed IN the release (mobile `b9810e72`, web `b01ea19`).
2. "More from this seller" on a shop listing shows the shop's stock, not the owner's personal
   listings (web and mobile).
3. Web: on their own shop listing a member may see the buyer view for a moment on first paint (the
   server render knows the viewer's id, not their shops; the page is fetched anonymously). Fixing it
   needs the viewer's shop ids in a cookie.

## Risk

- **Migration** `20261008210000`: `blocks.shop_id` (nullable, concurrent index). Additive.
- **The gate depends on the 1.1.7 bump**: the app sends `X-App-Version` from `app.json`. Until it
  says 1.1.7 the API treats the app as legacy: no privacy gain, but nothing breaks.
- **Deploy order:** the API and web go together (web always counts as new). Mobile users get it
  when they update to 1.1.7; until then the 1.1.6 app keeps today's payload.
- Cable payloads (no headers) get the strict output (no owner id) — only message payloads go
  there, and those were already fixed in `c714771`.

## Test evidence

- API: `spec/edge/privacy_b_spec.rb` (13) + `spec/models/current_spec.rb`; regression **2104/2104**
  (every spec touching listings, conversations, blocks, reports, app_config); RuboCop clean.
- Web: tsc + eslint clean; e2e `e2e/privacy-b.spec.ts` (6 cases) + the specs its mock change
  touches: _pending (shared e2e slot)_.
- Mobile: Jest **2410/2410** after the rebase (src/lib, src/api, chat, shared, settings, profile,
  components/common), incl. `identity.test.ts` (17, numeric AND null id), shop block/unblock/report
  API tests, BlockedUsers (shop row beside a person with the same id), holdInChat; no new tsc
  errors. No device run yet.

## Privacy text: DRAFT for 1.1.7 (needs the owner's approval)

With privacy-b a buyer never receives the user id behind a shop, so the profile can't be reached
from a shop chat. The sentence softened for 1.1.6 can be exact again. Proposed change to web
`messages/*.json` → `privacy.shopsBody`, one sentence in each locale, **not applied** until the
owner approves:

| | 1.1.6 (live) | 1.1.7 DRAFT |
|---|---|---|
| en | In chats with your shop, buyers see the shop's name and logo, not your personal details. | In chats with your shop, buyers see the shop's name and logo, never your personal name, photo or city. |
| ps | د دوکان په چټونو کې پیرودونکي د دوکان نوم او لوګو ویني، نه ستاسو شخصي معلومات. | د دوکان په چټونو کې پیرودونکي د دوکان نوم او لوګو ویني، هېڅکله ستاسو شخصي نوم، انځور یا ښار نه. |
| fa | در گفتگوهای دوکان، خریداران نام و لوگوی دوکان را می‌بینند، نه مشخصات شخصی شما را. | در گفتگوهای دوکان، خریداران نام و لوگوی دوکان را می‌بینند، هرگز نام شخصی، عکس یا شهر شما را نه. |
| ur | دکان کی چیٹس میں خریدار دکان کا نام اور لوگو دیکھتے ہیں، آپ کی ذاتی تفصیلات نہیں۔ | دکان کی چیٹس میں خریدار دکان کا نام اور لوگو دیکھتے ہیں، کبھی آپ کا ذاتی نام، تصویر یا شہر نہیں۔ |

The DRAFT wording is the pre-1.1.6 sentence, which the owner had already approved in all four
languages, and it is true again once privacy-b is live (API + web together, mobile from 1.1.7). It
should go live with the 1.1.7 API/web deploy, not before. Until 1.1.7 reaches the stores, a buyer
on the 1.1.6 app still gets the owner id, so "never" holds only for web and 1.1.7 apps. Better: keep
today's sentence until most users are on 1.1.7, then switch.

