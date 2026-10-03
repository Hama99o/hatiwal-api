# Hatiwal production infrastructure

**Written 2026-10-02.** Covers how Hatiwal's backend runs in production: what
runs where, how the databases are laid out, where secrets live, how to deploy,
back up and restore, and the move to a dedicated server.

Every number here was **measured** on the live server on 2026-10-02 unless it
says otherwise. Status markers: ✅ done · ⏳ in progress · 📋 planned.

---

> ✅ **MIGRATED 2026-10-02 ~18:20 (Paris).** Hatiwal (API, Postgres, Redis, photos,
> web, map) runs on the dedicated server `141.94.205.46`. Both repos'
> `.env.production` have `KAMAL_HOST=141.94.205.46`, so `bin/kms` and the map's
> `HOST` now target it.
>
> Data was copied after freezing the old API, and the counts matched exactly:
> 44 users · 69 listings · 36 conversations · 305 messages · 63 blobs ·
> 2 admins · last message #305.
>
> **Temporary, on the OLD server `51.254.130.18`:** the old API is stopped, and
> a forwarder `hatiwal_api_forward` (nginx, `~kamal/hatiwal-forward/api.conf`)
> sends `api.hatiwal.com` traffic to the new server, for devices still
> caching the old DNS (TTL 4 h). The old web/map containers and the old
> database stay as a fallback.
>
> Cleanup is due 2026-10-09. Remove from the old server: the forwarder, the
> Hatiwal containers, volumes, `~kamal/hatiwal-*` and `~kamal/hatiwal_api-*`.
>
> Nightly backup: `~kamal/bin/hatiwal-backup.sh` runs from cron at 03:15 UTC,
> into `~kamal/backups/hatiwal/`, and keeps the newest 7 (off-server copy: newest 7). The first run was at
> 16:20 UTC, and its restore test (44 users / 305 messages / 64 photos) passed.
> **Still to do:** the off-server copy (§6, layer 3).

## 1. Where Hatiwal runs

| | Server | IP | Status |
|---|---|---|---|
| **Today** | Shared OVH VPS `vps-30ee3e0c.vps.ovh.net` (4 vCPU, 7.6 GB RAM, 72 GB). Also hosts **edu_safi** and **multi_magic**. | `51.254.130.18` | ✅ live |
| **Target** | Dedicated OVH **VPS-2**, `vps-4814504b.vps.ovh.net` (4 vCore, 8 GB RAM, 75 GB NVMe, Gravelines). Order #260793534, 2026-10-02. | `141.94.205.46` | ✅ Ubuntu 24.04.4, hardened by `bin/server-bootstrap.sh` (2026-10-02); ⏳ Hatiwal not deployed yet |

**Why move:** on the shared server, another app's load, mistake or reboot hits
Hatiwal too, and Hatiwal has had **no backups** there (multi_magic does). A
dedicated server gives Hatiwal its own resources, its own backups and a clean
inventory.

**When:** the setup and a full rehearsal can happen now. The DNS switch happens
**after mobile 1.1.4 is live on both stores**, so the app and the server never
change together (`../../hatiwal-mobile/docs/RELEASE_1.1.4.md`).

---

## 2. What runs (one server, Hatiwal only)

```
                      Internet  (443 / 80)
                            │
                    ┌───────▼────────┐   TLS (Let's Encrypt), routing by host name
                    │  kamal-proxy   │   network: kamal
                    └─┬──────┬─────┬─┘
      hatiwal.com,www │      │ api │ map.hatiwal.com
              ┌───────▼──┐ ┌─▼───────────────┐ ┌──────────────────┐
              │ web      │ │ api (Rails/Puma)│ │ map_web (nginx)  │
              │ Next.js  │ │ + ActionCable   │ │   └ map_tiles    │
              │ :3000    │ │ + Solid Queue   │ │     (pmtiles)    │
              └──────────┘ └─┬────────────┬──┘ └──────────────────┘
               hatiwal_web-net │  hatiwal_api-net│
                         ┌─────▼──────┐ ┌───▼────┐
                         │ Postgres 16│ │ Redis 7│   127.0.0.1 only, never public
                         └────────────┘ └────────┘
```

| Service | Container (prefix) | Image | Network | Port | State on disk | Deployed by |
|---|---|---|---|---|---|---|
| **API**: Rails, Puma, ActionCable (`/hatiwal-cable`), Solid Queue in Puma | `hatiwal_api-web-<sha>` | `hama99o/hatiwal_api` | `hatiwal_api-net` | 80 (behind proxy) | photos volume (below) | `hatiwal-api`: `bin/kms deploy` |
| **Database** | `hatiwal_api-db` | `postgres:16` (16.13) | `hatiwal_api-net` | `127.0.0.1:5434` | `~kamal/hatiwal_api-db/data` | Kamal accessory `db` |
| **Redis** | `hatiwal_api-redis` | `redis:7-alpine`, appendonly | `hatiwal_api-net` | `127.0.0.1:6381` | `~kamal/hatiwal_api-redis/data` | Kamal accessory `redis` |
| **Photos / files** (ActiveStorage, Disk service) | inside the API | — | — | — | Docker volume `hatiwal_api_storage` → `/rails/storage` (68 MB, 64 files) | with the API |
| **Web** (hatiwal.com) | `hatiwal_web-web-<sha>` | `hama99o/hatiwal_web` | `hatiwal_web-net` | 3000 | none (stateless) | `hatiwal-web`: `bin/kms deploy` |
| **Map front door** | `hatiwal_map_web` | `nginx:alpine` | `kamal` | — | `~kamal/hatiwal-map/{nginx.conf,static}` | `hatiwal-map`: `deploy/deploy.sh` |
| **Map tiles** | `hatiwal_map_tiles` | `ghcr.io/protomaps/go-pmtiles` | `kamal` | — | `~kamal/hatiwal-map/tiles/afghanistan.pmtiles` (1.2 GB) | same |

**Footprint:** about 750 MB RAM (API ~540, web ~86, DB + Redis ~80, map ~20)
and about 1.3 GB of disk. The VPS-2 has 8 GB and 75 GB.

**Health checks** (kamal-proxy waits for these before switching traffic):
- API: `GET /up`
- Web: `GET /api/health`
- Map: `/styles/hatiwal-light-en.json`

---

## 3. Databases: one Postgres, four databases, nothing shared

A single Postgres 16 container, `hatiwal_api-db`, belongs to Hatiwal only.

| Database | Size | Holds | Back up? |
|---|---|---|---|
| `hatiwal_production` | 11 MB | **Everything that matters**: users, listings, conversations, messages, sales, reviews, admin data, ActiveStorage metadata. | **Always.** It's the only copy of the business. |
| `hatiwal_production_queue` | 8.8 MB | Solid Queue: pending and scheduled jobs (pushes, emails, deletions). | Yes, cheaply. Restoring it keeps scheduled jobs such as the 30-day account deletions. |
| `hatiwal_production_cache` | 7.8 MB | Solid Cache. | Optional; rebuilds itself. |
| `hatiwal_production_cable` | 7.8 MB | Solid Cable: ActionCable messages, kept 1 day. | No. |

Rules:
- **Never mixed with another app.** On the dedicated server only Hatiwal's
  containers run. On the shared server today edu_safi and multi_magic each
  have their own Postgres container and network. Hatiwal's database is reached
  only on `hatiwal_api-net`, and published only on `127.0.0.1:5434`, never on
  a public interface.
- **One role**, `hatiwal`, with the password in `POSTGRES_PASSWORD` /
  `DATABASE_PASSWORD` (secrets, §4).
- **Migrations:** `bin/kms migrate`, or the `migrate` alias. The cache, queue
  and cable schemas live in `db/{cache,queue,cable}_migrate`.

---

## 4. Configuration and secrets

| Where | What | In git? |
|---|---|---|
| `config/deploy.yml` | Service names, networks, ports, accessories, **the list** of secret env names (`env.secret`) and plain values (`env.clear`: `DATABASE_HOST=hatiwal_api-db`, `REDIS_URL=redis://hatiwal_api-redis:6379/0`, …). | yes |
| `.env.production` | The real values: `KAMAL_HOST`, `KAMAL_PROXY_HOST`, `SSH_USER=kamal`, registry token, Rails master key, DB password, JWT secret, admin password, CORS origins, feature flags. | **no** (gitignored) |
| `.kamal/secrets` | Reads each secret out of `.env.production` for Kamal. | yes (no values in it) |
| `config/credentials.yml.enc` | Rails credentials (Google client ids, …), decrypted by `RAILS_MASTER_KEY`. | yes (encrypted) |

**Deploy access:** SSH user `kamal` with key `~/.ssh/id_ed25519` on the owner's
PC (ed25519, `SHA256:NFAx1PqF…`). It's the same key for the API, web and map,
and the same key OVH stores as **hama-deploy**. There are no passwords.

**Feature flags held in production:**
- `SUPPORT_ADMIN_INITIATE=true`: on since 2026-10-01.
- `WELCOME_SUPPORT_MESSAGE=true`: **on since 2026-10-03**, once mobile 1.1.4
  was live on both stores. See `docs/SUPPORT_MESSAGING.md`.

Moving to a new server changes **one value**: `KAMAL_HOST` in each repo's
`.env.production` (hatiwal-api, hatiwal-web), and `HOST` for the map's
`deploy.sh`.

---

## 5. Deploying

```bash
# API (hatiwal-api)
bin/kms deploy        # build locally, push the image, zero-downtime switch
bin/kms migrate       # run migrations
bin/kms logs          # follow logs
bin/kms console       # Rails console
bin/kms rollback      # previous release

# Web (hatiwal-web)
bin/kms deploy

# Map (hatiwal-map): idempotent, recreates both containers
HOST=<vps-ip> SSH_USER=kamal SSH_KEY=~/.ssh/id_ed25519 ./deploy/deploy.sh
```

Images are built **on the owner's PC** and pushed to Docker Hub, so the server
needs no build tools or build RAM. If SSH drops mid-deploy, the image is already
pushed: re-run `kamal deploy --skip-push` (that is how the 2026-10-02 web deploy
finished).

**Order for a fresh server:**
1. `kamal setup` in hatiwal-api: installs Docker and kamal-proxy, creates the
   accessories (db, redis), deploys.
2. `kamal setup` in hatiwal-web.
3. The map's `deploy.sh`.

---

## 5b. Shortcuts (`bin/kms`): all tested against production 2026-10-02

Run them from the repo root. `bin/kms help` lists everything.

| Need | API (`hatiwal-api/bin/kms`) | Web (`hatiwal-web/bin/kms`) |
|---|---|---|
| Deploy / redeploy / roll back | `deploy` · `redeploy` · `rollback` | same |
| Deploy got cut off (SSH dropped) | `kamal deploy --skip-push` | `deploy:retry` |
| Is it up? | `health` (API + web + map) | `health` |
| Server load, RAM, disk, containers | `server` | — |
| Shell on the server | `ssh` | — |
| Live logs | `logs` | `logs` |
| Last N lines / a time window | `logs:200` · `logs:since 2h` | `logs:200` |
| Errors only | `logs:errors` | `logs:errors` |
| Background jobs and push | `logs:jobs` | — |
| Search the logs | `logs:grep <text>` | `logs:grep <text>` |
| Postgres / Redis / proxy logs | `logs:db [N]` · `logs:redis [N]` · `logs:proxy [N]` | `logs:proxy [N]` |
| Rails console / one-liner | `console` · `runner '<ruby>'` (quotes are safe) | — |
| DB console / Redis CLI | `psql` · `redis:console` | — |
| Migrations | `migrate` | — |
| **Full backup** (main DB + queue DB + all photos) | `backup` → `backups/<time>/` · `backup:list` | — |
| DB only | `db:dump` | — |
| Restore to production | `db:restore <file>` (takes a full backup first, asks `yes`) | — |

First full backup with photos: `backups/20261002_174447/` (52 KB + 8 KB of
gzipped SQL, 64 files / 67 MB of photos), on the owner's PC.

## 6. Backups ✅ (since 2026-10-02)

| Layer | What | When | Kept | Status |
|---|---|---|---|---|
| 1. OVH Automated Backup (included in VPS-2) | The whole server | Daily | OVH's rotation | ✅ on |
| 1b. OVH Snapshot option (€0.50 HT/month, order #260806206, 2026-10-02) | One manual restore point of the whole server (a new one replaces the old) | **Before any big server change** (system upgrade, Docker/Kamal upgrade, big release); take one first | 1 | ✅ ordered; first snapshot: after the migration |
| 2. App backup on the server: `~kamal/bin/hatiwal-backup.sh` (copy in `bin/hatiwal-backup.sh`) | `pg_dump` of `hatiwal_production` + `hatiwal_production_queue` (gzipped SQL), plus a `tar.gz` of the `hatiwal_api_storage` photos | Nightly, cron **03:15 UTC** | **newest 7**, one a day, i.e. a week (by count, so a stopped backup never ages out the good ones), in `~kamal/backups/hatiwal/<stamp>/`; log in `backup.log` | ✅ |
| 3. Off-server copy | Layer 2's folder, pushed by rsync to the **old VPS** `51.254.130.18:~kamal/offsite/hatiwal/` with a **write-only key** (rrsync, `from=` the new IP, cannot run a shell). No `--delete`: a broken primary can't wipe the copies. | Right after layer 2 | **newest 7** (pruned on that side, 04:30) | ✅ (`offsite ok` in `backup.log`) |
| 4. Restore test | Restore the latest dump into a scratch DB `restore_test`, count rows, drop it | Done 2026-10-02 (44 users / 305 messages / 64 photos); repeat monthly | — | ✅ first run |
| On demand | `bin/kms backup` → `backups/<time>/` on the owner's PC | When needed | Manual | ✅ |

**When the old VPS is cleaned up** (2026-10-09), keep `~kamal/offsite/hatiwal`
and its prune cron, or move layer 3 to object storage first.

The map tiles need no backup. They're one rebuildable file, and
`hatiwal-map/deploy/RUNBOOK.md` explains how to rebuild them.

## 7. Restoring

**Database** (from a plain SQL dump made by `bin/kms db:dump`):
```bash
bin/kms db:restore backups/hatiwal_api_YYYYMMDD_HHMMSS.sql   # ⚠ overwrites PRODUCTION
```

**Photos:**
1. Stop the API.
2. Extract the photos tar into the `hatiwal_api_storage` volume, keeping paths
   (`/rails/storage/xx/yy/<key>`).
3. Start the API.
4. Check one listing image URL returns 200.

Always restore into a scratch database first when you can, and check row counts
before touching production.

---

## 8. Moving to the dedicated server (runbook) ⏳

Nothing changes for users until step 6.

1. ✅ **Prepare the server** (2026-10-02). Run `ssh ubuntu@<ip> 'sudo bash -s' < bin/server-bootstrap.sh "$(cat ~/.ssh/id_ed25519.pub)"`; it is idempotent. Done, and verified from outside: kamal login, docker, ufw 22/80/443, root and password login refused, fail2ban, log caps. The `ubuntu` password (OVH forced a change) is kept only in `~/.ssh/hatiwal-vps-ubuntu.password` on the owner's PC, for the OVH KVM console.
   - Ubuntu 24.04, `kamal` user with the deploy key, root and password login off.
   - Firewall: allow only 22, 80, 443.
   - `unattended-upgrades`, `fail2ban`, time sync.
2. **Point Kamal at it:** set `KAMAL_HOST=141.94.205.46` in a copy of each
   `.env.production` (kept separate until cutover).
3. **Install:**
   - `kamal setup` (API: db + redis + app).
   - `kamal setup` (web).
   - The map's `deploy.sh`, then copy `afghanistan.pmtiles` across.
4. **Rehearsal:**
   - Copy the database (`pg_dump` → `pg_restore`) and the photos volume from
     the old server; nothing is written to it.
   - Test by IP / hosts file: login, listings, photos, chat (ActionCable), map,
     admin.
5. **Backups:** install §6 layers 2–4 and run the restore test.
6. **Cutover** (after 1.1.4 is on both stores):
   - The day before, lower the DNS TTL to its minimum.
   - Stop the old API.
   - Take a final dump of the database and photos, and restore them on the new
     server.
   - At Squarespace, change the **A records `@`, `www`, `api` and `map`** from
     `51.254.130.18` to `141.94.205.46`. Leave the TXT and CNAME records alone.
   - Check with the health checks, a real login and a real photo.
   - Expected downtime: 5–15 minutes.
7. **Rollback:** point the 4 A records back to `51.254.130.18` and start the
   old API. Keep the old copy untouched for **7 days**, then remove Hatiwal
   (containers, volumes, `~kamal/hatiwal-*`) from the shared server.

---

## 9. Security baseline

- **SSH:** keys only, user `kamal`, no root login, no password login.
- **Open ports:** 22, 80, 443. Postgres and Redis listen on `127.0.0.1` only.
- **TLS:** automatic, by kamal-proxy (Let's Encrypt).
- **Secrets:** only in `.env.production` (gitignored) and Rails encrypted
  credentials. Nothing secret in git: the Firebase file was removed from
  `hatiwal-mobile`'s history on 2026-10-02.
- **Updates:** unattended security upgrades. Images are rebuilt on every deploy.
