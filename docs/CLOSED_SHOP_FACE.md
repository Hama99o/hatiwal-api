# closed-shop-face — a closed shop's chats keep what was written as the shop

**For the owner's decision, 2026-10-09 09:00.** Built on SIDE branches; nothing is in
`release-1.1.6`. Independent of privacy-b (either can be taken without the other).

| Repo | Branch | Based on |
|---|---|---|
| api | `closed-shop-face` (worktree `.worktrees/api-closed-face`) — `a3ca16b` + this doc | api `release-1.1.6` `a2059e1` |
| web | `closed-shop-face-web` (`.worktrees/web-closed-face`) | web `release-1.1.6` `10fc332` |
| mobile | `closed-shop-face-mobile` (`.worktrees/mobile-closed-face`) | mobile `release-1.1.6` `648d2f25` |

## The question

When the owner closes a shop, its product chats go back to the owner (by design: the products
become theirs). In the release that also rewrites the PAST: every message the team wrote as the
shop now shows the buyer the writer's **personal name** — the owner's, and a former Staff
member's. The privacy text promised buyers "never your personal name".

## This branch

- Messages the team wrote **as the shop before the closure** keep the shop's name, marked
  **Closed** (the logo is deleted with the shop). The buyer never sees who wrote them; the owner
  still sees which member did ("replied by").
- Messages the owner writes **after** the closure are from the owner personally — as in the
  release — and both sides see a note at the composer: owner "*{shop} has closed — you're now
  replying as yourself*", buyer "*{shop} has closed — new messages come from the seller
  personally*".
- Inbox rows show the owner's name with "*{shop} · closed*", so the buyer understands the change.

## Risk

- **Migration** `20261008220000`: `shops.closed_at` (shops closed before it take their last
  update as the closing time — `close!` is their last write). Additive.
- New keys are additive and null outside closed-shop chats; registered in the v1.0.4 contract
  spec. Apps older than this branch show the shop's name on those old messages (no marker).

## Effect on the privacy text (1.1.6 draft, web `10fc332`)

Today's text (matching the release): "*When you close the shop, the shop page is removed at once,
and chats about its products continue with you personally, under your own name.*"

With this branch it would read: "*When you close the shop, the shop page is removed at once.
What your team wrote as the shop stays under the shop's name; new messages in its chats come
from you personally, under your own name.*"

## Test evidence

- API: `spec/edge/closed_shop_face_spec.rb` (6, failing first) + regression **1149** (every spec
  touching chats, messages, closing) + API contracts 12/12; RuboCop clean.
- Web / mobile: see their branch commits.
