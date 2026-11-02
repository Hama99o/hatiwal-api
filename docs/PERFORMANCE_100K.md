# Performance at 100k users (2026-10-12, branch `perf-1.1.7`)

The owner's question: *"Improve the search query so it doesn't take too much time. We have
pagination, but if we have 100,000 active users, will it break? Check our side and whether we
can improve it more."*

**Short answer.** Before this branch, yes: at 100k users several screens took 1 to 12 seconds
**per request with nobody else on the server**: search, "near me", a seller's inbox, the
`/users/me` badge poll for shop members. The cause was our queries, not the server. After this
branch every measured screen answers in 30 to 750 ms in a single process (one deep-page case
reaches ~880 ms at p95). Most screens are at 100 to 400 ms. What is left is mostly server size
(how many requests run at once), plus a few product choices listed under "Needs the owner".

Each claim is tagged **[measured]** (run on the scratch DB below) or **[inferred]** (reasoned,
not run).

## How it was measured

- **Data** [measured]: a scratch Postgres 16 DB, `hatiwal_perf`, on the dev box (local Docker
  `hatiwal-api-postgres-1`, default config: `shared_buffers` 128 MB, like the production
  accessory, which sets no tuning either). It was filled with bulk SQL (`generate_series`), then
  dropped at the end:

  | Table | Rows | Notes |
  |---|---|---|
  | users | 100,000 | 10 Afghan cities + Peshawar, weighted (Kabul 40%); ~1.5% suspended or banned |
  | shops | 2,000 | 95% active; owners are users 1–2000 |
  | listings | 300,000 | 82% active, 5% reserved, 8% sold, 5% draft; **220,061 browsable**; 90% have lat/lng; titles and descriptions in en / ps / fa words; 20% belong to 500 "power sellers"; user 1 has 3,005 (the worst case) |
  | photos | 600,000 attachments over 300 blobs | 1–3 per listing |
  | conversations | 154,390 | 30% on power sellers' listings; user 1 has 3,552 chats, user 2 (a shop owner) has 71 |
  | messages | 1,035,907 | 1–13 per chat, ps/fa/en bodies, ~50% of last messages unread |
  | saved_listings | 501,497 | user 3 saved 1,500 |
  | listing_views, hidden_listings, blocks, price drops, sales | 600k, 20k, 5k, 20k, 12k | |

  DB size: ~1.0 GB with the new indexes.
- **Timing** [measured]: each endpoint was called in-process through the whole Rails stack
  (`Rack::MockRequest` → routing → auth token → controller → serializer → JSON), 2 warm-up calls,
  then 6 timed calls. p50 and p95 are over those 6 (so p95 ≈ the slowest call). This was
  `RAILS_ENV=development`, one process, one request at a time, with another session's Android
  emulator running on the box. **Absolute numbers are for comparison only**: production
  (eager-loaded code, no dev reloader) runs the Ruby part faster [inferred]. The before/after
  ratio is what this table shows.
- **SQL**: each hot query was captured as Rails sends it and run with
  `EXPLAIN (ANALYZE, BUFFERS)` (summaries below). The `docs/LOAD_TEST.md` kit was **not** run
  (it needs the whole machine and the owner's OK). This document measures our code per request.
  The load test measures how many requests run at once.

## Before / after (ms, p50 / p95, same data, same machine)

"Power seller" = user 2 (a shop owner, 71 chats). "Mega seller" = user 1 (3,005 listings,
3,552 chats). Pages are 20 rows; "p200" = `page[number]=200` (OFFSET 3980).

| Endpoint | Before p50 / p95 | After p50 / p95 | SQL queries | Speed-up |
|---|---|---|---|---|
| Feed p1 (guest) | 630 / 662 | 208 / 260 | 12 → 12 | 3.0× |
| Feed p1 (signed in) | 1012 / 1084 | 265 / 298 | 16 → 16 | 3.8× |
| Feed p200 (signed in) | 1273 / 1316 | 441 / 514 | 16 → 16 | 2.9× |
| Search en `phone` | 2742 / 2867 | 373 / 399 | 16 → 16 | 7.3× |
| Search en `samsung galaxy` | 3214 / 3500 | 509 / 537 | 16 → 16 | 6.3× |
| Search ps `موټر` | 2866 / 3043 | 591 / 604 | 16 → 16 | 4.8× |
| Search fa `قالین` | 2942 / 3054 | 557 / 582 | 16 → 16 | 5.3× |
| Search, no match (`xyzq`) | 6161 / 6640 | 32 / 36 | 6 → 4 | 190× |
| Search `phone` p50 | 2986 / 3345 | 671 / 702 | 16 → 16 | 4.5× |
| Category + price range | 1038 / 1100 | 231 / 265 | 16 → 17 | 4.5× |
| Category + price p100 | 1298 / 1324 | 262 / 289 | 16 → 17 | 4.9× |
| Sort price_asc | 1030 / 1105 | 294 / 329 | 16 → 16 | 3.5× |
| Nearest-first, Kabul p1 | 1840 / 1904 | 344 / 382 | 17 → 17 | 5.4× |
| Nearest-first, Kabul p200 | 2245 / 2382 | 752 / 884 | 17 → 18 | 3.0× |
| Radius 10 km, Kabul | 1240 / 1329 | 456 / 529 | 16 → 16 | 2.7× |
| Shops filter (`seller_type=shop`) | 958 / 1003 | 229 / 241 | 16 → 16 | 4.2× |
| Shop page products | 521 / 597 | 176 / 287 | 12 → 12 | 3.0× |
| Seller listings (mega seller) | 471 / 521 | 209 / 248 | 10 → 10 | 2.3× |
| Listing detail | 148 / 181 | 80 / 88 | 26 → 25 | 1.9×* |
| Similar rail | 432 / 447 | 94 / 102 | 16 → 15 | 4.6× |
| Inbox (normal user) | 119 / 132 | 55 / 57 | 17 → 16 | 2.2× |
| **Inbox (power seller, shop)** | **2124 / 2249** | 98 / 104 | 24 → 16 | 22× |
| **Inbox (mega seller)** | **6523 / 7180** | 111 / 163 | 24 → 16 | 59× |
| Inbox p10 (mega seller) | 7192 / 7470 | 94 / 98 | 24 → 16 | 76× |
| Inbox search (mega seller) | 12364 / 12582 | 515 / 560 | 24 → 16 | 24× |
| Messages (a thread) | 65 / 70 | 31 / 37 | 9 → 9 | 2.1×* |
| **`/users/me` (power seller, shop)** | **855 / 892** | 52 / 54 | 13 → 13 | 16× |
| `/users/me` (mega seller) | 1374 / 1438 | 100 / 120 | 13 → 13 | 14× |
| `/users/me` (normal user) | 63 / 72 | 27 / 30 | 9 → 9 | 2.4×* |
| Saved listings (1,500 saved) | 550 / 609 | 268 / 313 | 15 → 15 | 2.0× |
| Saved listings p50 | 650 / 660 | 332 / 447 | 15 → 15 | 2.0× |

\* These paths' queries did not change. Their gain is part a warmer cache in the second run and
part the shared index on non-active users. Read it as "unchanged, already fine".

`/users/me` matters most of all. Every open app calls it **every 60 s** for the unread badge.
Before this branch, every shop member's poll cost ~0.9 s of database time.

## What was fixed (6 code changes + 2 migrations)

1. **Every public listing query scanned the whole users table** [measured].
   `Listing.from_active_sellers` is `user_id NOT IN (SELECT id FROM users WHERE status != 0)`.
   A `!=` cannot use the `status` btree, so each feed, search, count, seen-lookup and saved-lookup
   query did a sequential scan of all 100k users. That cost ~85 ms each, up to 4 times per
   request. **Fix**: a tiny partial index `index_users_on_id_not_active (id) WHERE status <> 0`
   (56 kB). The page query went from 88 ms to 3 ms.
2. **Search used `LIKE '%word%'`, which no btree can serve** [measured]. A word with few or no
   matches walked the whole feed index looking for 20 rows (6.2 s). **Fix**: `pg_trgm` plus GIN
   trigram indexes on exactly the expressions `Listing.search` filters on, `lower(title)` and
   `lower(description)` (18 MB + 48 MB). Postgres combines them (BitmapOr). Pashto and Dari
   words use the index just as English does (checked: `موټر`, `قالین`). The search SQL is
   unchanged, so results are identical. The migration also runs `ANALYZE`: without fresh
   statistics on the new expressions, the planner ignored the indexes (measured: 2.2 s instead
   of 32 ms).
3. **The feed's total count** (pagination meta) was a parallel sequential scan of all 300k
   listings: 260 ms [measured]. **Fix**: a partial covering index
   `index_listings_browsable_feed (bumped_at DESC) INCLUDE (user_id, shop_id, expires_at,
   category_id, price) WHERE status IN (1,2) AND removed_at IS NULL` (17 MB). The count becomes
   an index-only scan (72 ms). Deep pages walk the index instead of the heap (139 ms → 26 ms at
   OFFSET 3980).
4. **Seen / saved hearts looked up the whole feed, not the page** [measured]. `viewed_ids` and
   `saved_ids` were `WHERE listing_id IN (<the entire unpaginated browsable query>)`, ~170–200 ms
   each, on every signed-in feed request. **Fix**: `paginate_blue` now accepts a lambda in
   `extra:` and calls it with the loaded page. The lookups are `listing_id IN (<20 ids>)`. The
   payload is identical. (The similar rail also had a latent bug here: `reorder(nil)` on its
   `limit(8)` could look up a different 8 rows. It now uses the rows it renders.)
5. **The inbox loaded the whole inbox before paginating** [measured].
   `conversations.map(&:id)` (for the unread counts) loaded every conversation of the user with
   all includes: each chat's messages, listing photos, avatars. That was 6.5 s for 3,552 chats.
   **Fix**: unread counts are computed for the page's conversations only (same lambda
   mechanism, same GROUP BY query).
6. **Shop members' inbox and badge scanned all 150k conversations** [measured]. The team rule
   `seller_id = :u OR EXISTS (SELECT 1 FROM shop_members ... = conversations.shop_id)` is
   correlated, so Postgres ran it once per conversation row (~500 ms, twice per
   `/users/me`). **Fix**: `shop_id = ANY (ARRAY(SELECT shop_id FROM shop_members WHERE user_id
   = :u))`. The member's shops are read once, and the three conditions become an OR of three
   index scans (11 ms). Same rows: a NULL `shop_id` matches neither form.
7. **Category filter** [measured]: `by_category` passed its ids as a subquery, so Postgres
   could not estimate the category's share of the feed and chose a poor plan for
   category + price pages (118–220 ms SQL). **Fix**: the ~6 ids are read first (one query on
   83 categories) and inlined: 58–106 ms.
8. **Nearest-first** [measured]: the window check counted every listing in a 50 km circle just
   to learn "are there at least 20?" (~220 ms in Kabul). Then it sorted all ~85k Kabul rows by
   Haversine distance (~300 ms). **Fix**: the check is `limit(needed).count`, which stops at the
   page size, and smaller radii (2, 5, 15 km) were added before 50 km. A dense city now sorts a
   few thousand rows. The page is identical by construction: the existing "same pages as an
   unboxed sort" spec still passes.

Migrations (`db/migrate/20261012100000_enable_pg_trgm.rb`,
`20261012100100_add_feed_and_search_indexes.rb`) are production-safe: every index is
`algorithm: :concurrently` with `disable_ddl_transaction!`, so no write lock on listings or
users. `pg_trgm` is a trusted extension, and the production DB user `hatiwal` is the
container's `POSTGRES_USER` (superuser) anyway. Build time on 300k listings was ~50 s, mostly
the description trigram index [measured]. On today's production size it takes seconds
[inferred].

Specs: `spec/requests/api/v1/performance_100k_spec.rb` pins each fix with the same payloads and
less work (page-scoped lookups, page-only inbox load, no `EXISTS`, inlined category ids, limited
window count, indexes present). `listings_nearest_spec.rb` was updated for the new smallest
radius.

## What remains (not changed, on purpose)

- **Total counts on broad results** [measured]. Every paginated list returns an exact
  `total_count`. Web Browse shows it ("12,345 listings") and both apps derive "is there a next
  page" from `total_pages`. On the whole feed that count is now ~72–110 ms. On a search that
  matches a third of the catalogue it is ~220 ms. A capped or estimated count, or no count, would
  remove it, but **it changes what the clients show**, so it is flagged, not done (see "Needs the
  owner"). The seeded vocabulary is only 30–40 words per language, so a "common word" here
  matched up to 120k rows. Real searches match far fewer, and search will be faster than shown
  [inferred].
- **Deep pages use OFFSET** [measured]: page 200 still reads ~4,000 rows to skip them
  (441 ms vs 265 ms on page 1). Keyset ("cursor") pagination would fix it, but both clients send
  `page[number]`. That is a client change, so it is flagged. Real users rarely scroll 200 pages
  [inferred].
- **Nearest-first deep pages and radius filters in a dense city** [measured]: page 200 of "near
  me" in Kabul needs the 4,000 nearest rows, so a 15 km box gets sorted (~750 ms). The radius
  filter's total count computes Haversine distance for every Kabul row (~200–260 ms). PostGIS
  with a GiST index would make both cheap. That is a bigger change (new extension, new column),
  so it is left for later.
- **Ruby serialization of the listing cards** [measured]: ~130–150 ms of the 200 ms guest feed
  in dev mode is Ruby. Each card builds 3 lazy image URLs per photo (original, thumb, medium),
  each ~0.4 ms of route generation and signing. That is CPU per request and scales with Puma
  processes, not with the database. Production is faster [inferred].
- **Inbox `latest_message` preload** loads all messages of the 20 chats on the page, to pick
  the newest of each [measured: fine at ≤13 messages per chat]. A chat with hundreds of
  messages would load hundreds of rows per inbox page [inferred]. A `DISTINCT ON` preload would
  fix it if long threads become common.
- **Inbox search for a seller with thousands of chats**: ~500 ms (`ILIKE` over all their
  messages) [measured]. It is fine for normal users. A trigram index on `messages.body` would
  cost ~100+ MB at 1M messages, which is not worth it yet.
- **Saved listings with 1,500 saves**: 268 ms, of which ~100 ms is the count reading 1,500 random
  listing rows [measured]. That is an extreme saver, so it was left.
- **Not measured**: writes (create listing with photos, send message, broadcast), ActionCable
  fan-out, Solid Queue throughput, photo variant generation. These are what `docs/LOAD_TEST.md`
  measures.

## Verdict for 100k active users

**Our code** [measured]: with this branch, no read endpoint grows with the size of the
database the way it did before. A user's inbox costs the same at 70 or 3,500 chats (~100 ms).
The badge poll is ~30–100 ms. The feed, filters and search answer in ~0.2–0.6 s per request in
dev mode on a laptop-class box, with 220k live listings. Before this branch the same requests
took 1–12 s, and several of them grew with the total number of users or chats. At 100k users
that alone would have made the app feel broken, whatever the server.

**What depends on the server** [inferred, from config, not load-tested]:
- **Puma**: production runs **one Puma process with 3 threads** (`config/puma.rb`, no
  `WEB_CONCURRENCY`), with Solid Queue inside it. Ruby runs one thread at a time per process,
  so one process serves roughly 5–15 feed requests per second. "100k users" is not 100k at once.
  If ~2% are online at peak (2,000 people), each browsing every ~10 s and polling
  `/users/me` every 60 s, that is ~200–250 requests per second. That needs **several Puma
  processes** (`WEB_CONCURRENCY` ≈ number of cores) and, at the top end, more than the current
  4-vCore VPS-2, or a second app server.
- **Postgres**: the hot working set at this scale is ~1 GB (listings 142 MB, messages 123 MB,
  indexes). The production accessory runs Postgres defaults (`shared_buffers` 128 MB). Set
  `shared_buffers` ≈ 1–2 GB and `effective_cache_size` ≈ 4 GB on an 8 GB box. Connections:
  pool = threads per process, so 4 processes × 3 threads + queue workers ≈ 20, well under the
  default `max_connections` of 100. Autovacuum must keep up, because the feed count is
  index-only only while the visibility map is fresh, and `views_count` updates keep dirtying
  listing pages.
- **Chat (ActionCable)**: production uses **solid_cable**, which polls the database every
  0.1 s, not Redis. Thousands of open sockets also hold memory in the Puma process. At 100k users
  with a few thousand sockets open, moving ActionCable to the Redis adapter (Redis already runs
  as an accessory) or to a separate cable process is the next step.
- **Run `docs/LOAD_TEST.md`** on this branch (with the owner's OK) to put a real number on
  "requests per second per process" before choosing the server size.

## Needs the owner's decision

1. **Exact total counts on the feed and search.** Keep them (≈70–220 ms per page at this
   scale), or switch to "1,000+" style capped counts, or "has a next page" only. That changes
   web Browse's "N listings" line and how the apps detect the last page.
2. **Cursor pagination** for the feed (fast deep pages). Both clients would need a change.
3. **Server sizing**: `WEB_CONCURRENCY`, Postgres `shared_buffers`, and whether chat moves to
   Redis-backed ActionCable. Best decided after the load test.
