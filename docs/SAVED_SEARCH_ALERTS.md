# Saved-search alerts (1.2.1) — API

Board card 381 (IDEA-7). The approved spec, with the UI and the decisions, is hatiwal-mobile
`docs/design/SAVED_SEARCH_ALERTS.md`.

## Pieces
| Piece | What it does |
|---|---|
| `saved_searches.query` / `.alert` | The browse keyword (part of the de-dupe), and the explicit opt-in. Followed searches are never pruned with the 4-chip history; at most `SavedSearch::MAX_ALERTS` (5) per user (422 `alerts_limit`). |
| `SavedSearch#matches?(listing)` | THE definition of a match, shared with the chip badge (`matching_listings`): browsable, no block pair, category (its children too), price, keyword (`Listing.search`), location / radius. Never the searcher's own listing. |
| `Listing` `after_update_commit … if: :went_live?` | Enqueues `SavedSearchMatchJob` (the same hook scam-photo uses). |
| `SavedSearchMatchJob` | SQL on alerted rows only (account switch on, not the seller, category or parent or none, price in range), then `matches?` per candidate. One `saved_search_alert_hits` row per (search, listing) — a listing that goes live twice counts once. Increments `pending_alert_count` and schedules the alert. |
| `SavedSearchAlerts` | The timing rules: 1 push per search per 6 h (batched), quiet 22:00–07:00 on the user's clock (`LocalTimeZone`: Kabul, or Karachi from a Pakistani province), 3 alert pushes per user per local day. One scheduled job per search. |
| `SavedSearchAlertJob` | Re-checks everything at send time and makes ONE decision, logged as `saved_search_alert event=… saved_search_id=… user_id=…` (ids only): `off`, `stale` (every pending listing gone), `window`, `quiet`, `capped` (rescheduled, never dropped), `no_token`, `sent count=N`. The push is in the user's language (`User#push_locale`, keys `push.saved_search.*` in 4 locales), data `{ type: "saved_search", savedSearchId }`. |
| `users.saved_search_alerts` | The account-wide switch (`PUT /users/me`). |

## Endpoints
- `GET /users/saved_searches`: the 4 most recent PLUS every followed search; `query`, `alert` in the JSON.
- `POST /users/saved_searches` accepts `query` and `alert` (the results banner follows in one request).
- `PUT /users/saved_searches/:id` `{ alert }`: follow / unfollow; owner only; 422 `alerts_limit`.

## Deploying
Migration `20261030140000_add_saved_search_alerts` (3 columns on users, 5 on saved_searches,
the `saved_search_alert_hits` table) runs with the deploy. No backfill: nothing is followed
until a user turns an alert on. To read the decisions after release:
`bin/kms app logs | grep saved_search_alert`, counted by `event`.
