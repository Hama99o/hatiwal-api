# Warnings — API contract (1.1.7)

Prohibited-item strikes ("warnings") shown in the apps. Owner, 2026-10-16:
**the business answers for what it sells** — a shop listing taken down with a
warning strikes BOTH the poster's account AND the shop. All keys below are
additive and 1.0.4-safe (old clients ignore them).

## User — the signed-in person

Two ways to read a user's warnings; both already exist and are unchanged in shape:

- `GET /api/v1/me/users/warnings` → `{ warnings: [{ id, category, reason, created_at, expires_at, acknowledged_at, active }], meta: { active_count, threshold } }`, plus `PUT …/mark_seen`. **Use this on the profile banner** (it is the list + the count + the threshold).
- The `/users/me` auth payload also carries, for convenience:
  - `active_warnings_count` (integer)
  - `warning_threshold` (integer, 3)
  - `latest_warning`: `null | { category, reason, created_at, listing_title }` *(new in 1.1.7)*

`threshold` / `warning_threshold` = `User::WARNING_BLOCK_THRESHOLD` = **3**. At 3
active warnings the account is suspended.

## Shop — members only

Endpoint: `GET /api/v1/shops/:id`. It returns the `:owner` view to a **member**
(owner or team) and the `:public` view to everyone else. These keys are in the
`:owner` view ONLY — a buyer/stranger on the public shop face NEVER sees them.

Response is rooted under `"shop"`:

```json
{ "shop": {
  "active_warnings_count": 1,
  "warnings_threshold": 3,
  "latest_warning": {
    "category": "prohibited_item",
    "reason": "Prohibited item (firearms): Kalashnikov (flag #12)",
    "created_at": "2026-10-16T09:00:00Z",
    "listing_title": "Kalashnikov"
  }
} }
```

`latest_warning` is `null` when the shop has none. `warnings_threshold` =
`Shop::SHOP_WARNING_BLOCK_THRESHOLD` = **3**.

A shop's warnings do **NOT** count toward the owner's personal 3 — they are
shop-scoped.

## Strikes and suspensions (for the banners)

- **A shop listing taken down "+ warning"** → the **poster's account** gets a strike
  (3 → the account is suspended) AND the **shop** gets a strike (3 → the shop is
  suspended). A listing **not** in a shop strikes only the poster (unchanged).
- **A shop reaches 3 active warnings → the shop is SUSPENDED**: hidden from
  search and the feed, its listings unavailable to buyers, saved/chat/map/public
  shop page all closed to non-members. The team keeps access and is told (team
  notification + Support message). Banner wording: *"At 3 the shop is suspended
  and its listings are hidden."*
- **A user reaches 3 active warnings → the account is SUSPENDED**: all their
  personal listings go down. **If that user is a shop OWNER, the shop goes dark
  too** for as long as the owner is suspended — a *computed* rule, not a second
  manual suspension: reinstating the owner brings the shop back automatically.
  A suspended **plain team member** only loses their own access; the shop stays up.
- **Coming back**: an admin reactivates a suspended shop (Shop reactivate) or
  unsuspends a user; their still-active listings reappear (they are not drafted).
  The one listing that was taken down stays a draft.

## Messages the apps don't render but should expect in Support

- Poster: "a warning was added to your account (N of 3)…" in their own Support thread.
- Shop owner: a message in the shop's Support thread naming the member who posted
  the item and the shop's strike count ("N of 3").

Both are sent in the reader's language (en / ps / fa; others read English).
