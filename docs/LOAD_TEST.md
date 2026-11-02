# Load test — the production API image, locally (prepared 2026-10-09, for 1.1.7)

**Status: prepared, NOT run yet.** It is meant for a quiet evening on the dev box, with the
owner's OK. It uses the whole machine for about an hour, so first stop the emulators and any
e2e runs, and tell the other sessions.

## What it answers

How does the API behave as it would on the production VPS, as users go from 10 to 500?
- latency (p95) and error rate per endpoint;
- CPU and memory of the API and of Postgres;
- what a burst of new photos costs (thumb / medium variants generated on first request);
- how fast a chat message reaches the other side over ActionCable.

## The setup (`loadtest/`)

| Piece | What | Why |
|---|---|---|
| `compose.yml` | `loadtest-api` = **the production image** (`hatiwal-api:loadtest`, built from this checkout's `Dockerfile`), `RAILS_ENV=production`, one Puma process / 3 threads / Solid Queue in Puma / Thruster on :80 — exactly as Kamal runs it. `loadtest-db` = `postgres:16` (the prod accessory). `loadtest-redis`. | Measure the real thing, not dev mode. |
| caps | api **3 CPU / 3 GB**, db **1 CPU / 1 GB**, redis 0.25 / 128 MB | Production is an OVH **VPS-2: 4 vCore, 8 GB**, shared by the API, Postgres, Redis, the web app and the map (measured footprint ~750 MB: API ~540). Kamal sets no per-container limits, so these caps model the API's and the DB's real share. k6 runs uncapped in its own container. |
| network | `internal: true` — **no route to the internet** | Production config sends real mail (Gmail SMTP) and real pushes (Expo). With no way out, nothing a load test triggers can reach a real person. |
| database | its own Postgres container + volume (`hatiwal-loadtest_loadtest_pg`); inside it the DBs keep their production names (`hatiwal_production`, `_cache`, `_queue`, `_cable`), because `database.yml` fixes them | Never the dev, QA or production DB. `seed.rb` refuses to run unless `LOADTEST=1` and the DB host is `loadtest-db`, and prints `DB: loadtest-db/hatiwal_production`. `run.sh up/seed` print the container id and DB list. |
| `seed.rb` | **2 000 users, 5 000 listings** (85 % active, 5 % each reserved / sold / draft; AF + PK cities; 1–3 photos each), **300 distinct photo blobs** (the CC0 seed photos, 1280 px), **4 000 conversations, 20 000 messages**. Bulk inserts; sizes via `LT_USERS`, `LT_LISTINGS`, `LT_CONVERSATIONS`, `LT_MESSAGES`, `LT_BLOBS`. | Realistic volume. Distinct blobs, so each needs its own thumb / medium (one shared blob would be generated once and hide the cost). |
| tokens | `seed.rb` writes auth headers for 600 users to `loadtest/tokens/tokens.json` (gitignored) | Nobody signs in during the run: `sign_in` is throttled to 20 per 5 min per IP, and k6 is one IP. Each VU is one user, so per-user throttles see a realistic spread. |
| key | `run.sh` reads `config/master.key` into the environment (never printed, never in a file it writes). | The production image needs it to boot. |

## The scenarios (`loadtest/k6/`, k6 0.54)

| File | What | Load |
|---|---|---|
| `variants.js` | **Photo variants, first generation vs cached.** Phase `first`: 1 500 listings opened once each (20 at a time); every thumb + the first medium is requested (`redirects: 0`), so each request runs libvips inside a Puma thread. Phase `cached`: the same URLs again, which is now only a lookup and a redirect. Tagged `variant_first` / `variant_cached`. | 20 VUs; run it **first, on a fresh seed** |
| `mixed.js` | **The main run: the app's real mix.** Per iteration, a user either browses (50 %: feed pages 1–3, search, "near me" by distance, 30 % a category), opens a listing (25 %: detail, 2 thumbs, the first medium, the similar rail), or chats (15 %: inbox, a thread, one in three sends a message, mark read). Then always `GET /users/me`, the app's 60 s unread poll. 2–6 s think time. | **ramp 10 → 100 → 250 → 500 VUs**, 3 min plateaus, 3 min at 500 (`STAGES` overrides) |
| `cable.js` | **Chat over ActionCable.** Each VU opens `/hatiwal-cable` with its token, subscribes to its first conversation and holds it 60 s. One VU in five sends a message over HTTP every ~20 s and measures `cable_delivery_ms` until it comes back on the stream (solid_cable polls every 0.1 s). | same ramp |
| `publish.js` | **Publish with 3 photos.** Multipart `POST /my/listings` (3 × a real 1280 px photo), then `PUT /my/listings/:id/publish`; a different user each time (30 creates/day/user). | constant **30 / min** for 10 min (`PUBLISH_PER_MIN`) |

Throttled requests (429: messages 120/h/user, creates 30/day/user) are checked separately
("send not throttled", "create not throttled"), so a throttle never hides a slow server.

## How to run it

```bash
cd hatiwal-api                     # the checkout to measure (release-1.1.7 or later)
loadtest/run.sh build              # the production image, ~5–10 min
loadtest/run.sh up                 # db + redis + api; prints the DB; waits for /up
loadtest/run.sh seed               # categories + the volume (~5 min); prints the DB
loadtest/run.sh stats &            # CPU / memory every 5 s → loadtest/results/stats.log
loadtest/run.sh k6 variants        # fresh seed only: first-generation vs cached photos
loadtest/run.sh k6 mixed           # the main ramp, ~15 min
loadtest/run.sh k6 cable           # ~15 min
loadtest/run.sh k6 publish         # 10 min
kill %1                            # stop stats
loadtest/run.sh down               # or `reset` to delete the load-test data
```

To rerun `variants` from cold: `reset`, `up`, `seed` again.

## What to record (`loadtest/results/`, one row per scenario in the table below)

- **Latency**: p50 / p95 / p99 of `http_req_duration` per tag: `browse`, `search`, `near`,
  `listing`, `similar`, `inbox`, `thread`, `send`, `me`, `create_3_photos`, `publish`,
  `variant_first`, `variant_cached` (from `*-summary.json`).
- **The VU count where p95 crosses the thresholds**: browse / listing 800 ms, `/users/me`
  500 ms, create 3 s, publish 1 s, cable delivery 2 s. That count is our capacity.
- **Error rate**: `http_req_failed` (< 1 %), split by status. 5xx means the server; 429 means
  a throttle working as designed.
- **CPU / memory**: `results/stats.log`, both `loadtest-api` and `loadtest-db`. Note the
  peak, whether the API hits its 3 CPU cap, and whether memory keeps growing (a leak) or
  plateaus.
- **Photo generation**: `variant_first` vs `variant_cached` p95. Also how many Puma threads
  are busy generating during `first`: browse latency in the same window shows whether a
  photo burst starves the feed. Count of `active_storage_variant_records` after `first`
  (`run.sh` → `docker compose exec loadtest-api bin/rails runner 'p ActiveStorage::VariantRecord.count'`).
- **Solid Queue**: pending jobs during and after `mixed` (pushes are queued per message),
  `SolidQueue::ReadyExecution.count`: does it drain, or grow?
- **Postgres**: `select count(*) from pg_stat_activity` at the peak (pool = 3 threads + the
  queue workers) and the slowest statements (`pg_stat_statements` if enabled).

| Scenario | Date / commit | Peak VUs OK | p95 browse | p95 listing | p95 me | p95 send | cable p95 | variant first / cached | 5xx % | API CPU / mem peak | DB CPU / mem peak | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | | |

## Limits of this test (read before trusting the numbers)

- It runs on the dev box, not the VPS: the CPU model differs, and caps model only a share.
  Compare runs with each other, not with production to the millisecond.
- k6 and the API share the host. Keep the box quiet, and watch k6's own CPU.
- Photos are shared between listings (300 blobs for ~10 000 attachments). Deleting a
  load-test listing would purge a blob others use; this data is throwaway (`reset`).
- No internet means no real pushes or mail, so their cost isn't measured, only the jobs
  that would send them.
