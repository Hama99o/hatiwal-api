# privacy-b — no owner id in what a buyer sees of a shop

**For the owner's decision, 2026-10-09 09:00.** Built overnight on SIDE branches; nothing is in
`release-1.1.6`. Choose: merge into 1.1.6, or keep it for 1.1.7.

| Repo | Branch | Head | Based on |
|---|---|---|---|
| api | `privacy-b` (worktree `.worktrees/api-privacy-b`) | `61759e0` + this doc | api `release-1.1.6` `d920412` |
| web | `privacy-b-web` (`.worktrees/web-privacy-b`) | `f1c12da` | web `release-1.1.6` `b01ea19` |
| mobile | `privacy-b-mobile` (`.worktrees/mobile-privacy-b`) | `2bf61082` | mobile `release-1.1.6` `b9810e72` |

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
- **Legacy gate** — clients older than 1.1.6 keep the owner id, so store apps that predate shops do
  not break: a client is "new" only with `X-App-Version` ≥ 1.1.6 or `X-App-Platform: web`. Every
  store build before 2026-10-01 sends no version at all → legacy.
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
- **The gate depends on the release bump**: the app sends `X-App-Version` from `app.json`, which
  says `1.1.5` until the release bump to 1.1.6. Without the bump the API treats 1.1.6 as legacy —
  no privacy gain, but nothing breaks.
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
