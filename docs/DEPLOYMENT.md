# Deployment Guide

## Overview

Hatiwal API is deployed with **Kamal 2** (zero-downtime) to the shared OVH VPS
`51.254.130.18`, alongside `multi_magic`, `edu_safi` and the `hatiwal_web`
front-end. See the workspace overview: [../../DEPLOYMENT.md](../../DEPLOYMENT.md).

### Current values (source of truth: `config/deploy.yml`)

| | value |
|---|---|
| Service / image | `hatiwal_api` / `hama99o/hatiwal_api` |
| Hostname | `api.hatiwal.51.254.130.18.nip.io` (auto-TLS) |
| Docker network | `hatiwal_api-net` (isolated) |
| Container port | `80` (Thruster → Puma) · healthcheck `GET /up` |
| Postgres host port | **`127.0.0.1:5434`** (avoids multi_magic 5432 / edu_safi 5433) |
| Redis host port | **`127.0.0.1:6381`** (avoids multi_magic 6379 / edu_safi 6380) |
| Databases | `hatiwal_production` (+ Solid Cache/Queue/Cable DBs, auto-created on boot) |

> Accessory host ports are bound to `127.0.0.1` only — never exposed publicly.
> Each co-hosted app **must** use a unique PG/Redis host port; that's why Hatiwal uses 5434/6381.

---

## Architecture

```
Internet :443
    ↓
kamal-proxy (shared, TLS termination, routes by hostname)
    ↓  api.hatiwal.51.254.130.18.nip.io
hatiwal_api (Rails API · Thruster→Puma on :80)   ── network: hatiwal_api-net
    ↓
PostgreSQL 16 (:5434) + Redis 7 (:6381)  — accessories on the same VPS
```

---

## Prerequisites

### Server Requirements
- Ubuntu 22.04 VPS (2GB RAM minimum)
- Docker installed
- SSH access with deploy key

### Local Requirements
- Docker installed
- Kamal 2 (`gem install kamal`)
- SSH key configured for the server

---

## Configuration Files

### `config/deploy.yml`

The committed `config/deploy.yml` is the source of truth — read it directly. Key points:

- `service: hatiwal_api`, `image: hama99o/hatiwal_api`, all hosts/proxy/SSH driven
  by env vars (`KAMAL_HOST`, `KAMAL_PROXY_HOST`, …) from `.env.production`.
- `proxy.app_port: 80` with `healthcheck.path: /up`; `servers.web.options.network: hatiwal_api-net`.
- `env.clear` sets `DATABASE_HOST: hatiwal_api-db`, `DATABASE_PORT: 5432`,
  `DATABASE_USERNAME: hatiwal`, `REDIS_URL: redis://hatiwal_api-redis:6379/0`,
  `SOLID_QUEUE_IN_PUMA: true` (background jobs run inside Puma — no separate worker).
- `env.secret`: `RAILS_MASTER_KEY`, `DATABASE_PASSWORD`, `DEVISE_JWT_SECRET_KEY`, `APP_DOMAIN`.
- Accessories pin the **host** ports to `127.0.0.1:5434:5432` (Postgres) and
  `127.0.0.1:6381:6379` (Redis) so they don't collide with the other co-hosted apps.

Set up your real values once:

```bash
cp .env.production.example .env.production
#   DATABASE_PASSWORD / DEVISE_JWT_SECRET_KEY  →  openssl rand -hex 32  (no '=' chars)
#   KAMAL_REGISTRY_PASSWORD                    →  Docker Hub access token
#   RAILS_MASTER_KEY is read from config/master.key by .kamal/secrets
```

### `.kamal/secrets`

Reads secrets from `.env.production` (and `config/master.key`) to feed Kamal:

```bash
KAMAL_REGISTRY_PASSWORD=$(cat .env.production | grep KAMAL_REGISTRY_PASSWORD | cut -d= -f2)
RAILS_MASTER_KEY=$(cat config/master.key)
DATABASE_PASSWORD=$(cat .env.production | grep DATABASE_PASSWORD | cut -d= -f2)
POSTGRES_PASSWORD=$(cat .env.production | grep DATABASE_PASSWORD | cut -d= -f2)
DEVISE_JWT_SECRET_KEY=$(cat .env.production | grep DEVISE_JWT_SECRET_KEY | cut -d= -f2)
APP_DOMAIN=$(cat .env.production | grep APP_DOMAIN | cut -d= -f2)
```

---

## Deploying

### First-time Setup

```bash
# One-time: create this app's isolated Docker network on the VPS
ssh kamal@51.254.130.18 "docker network create hatiwal_api-net"

# Bootstraps the server + boots accessories (Postgres + Redis) + first deploy.
kamal setup

# Migrations run automatically on boot (bin/docker-entrypoint → db:prepare, which
# creates the primary + Solid Cache/Queue/Cable databases). To run by hand:
bin/kms migrate
bin/kms seed          # seed categories
```

### Regular Deploys

```bash
bin/kms deploy        # deploy latest code
bin/kms status        # deployment details (kamal details)
bin/kms logs          # follow logs
bin/kms rollback      # revert to previous version
```

---

## KMS (Kamal Management Script)

`bin/kms` is already committed — a friendly wrapper over `kamal`. Run `bin/kms help`
for the full list. Common operations:

```bash
bin/kms deploy        # build + push + zero-downtime deploy
bin/kms status        # deployment details
bin/kms logs          # follow app logs   (logs:200, logs:db, logs:redis, logs:proxy)
bin/kms console       # Rails console on production
bin/kms migrate       # bin/rails db:migrate
bin/kms psql          # production Postgres console (psql -U hatiwal hatiwal_production)
bin/kms db:dump       # download prod DB → ./backups/
bin/kms db:load       # load latest dump into the LOCAL docker-compose DB
bin/kms db:restore f  # restore a dump to PRODUCTION (asks to confirm)
bin/kms rollback      # revert to the previous release
```

---

## Environment Variables (Production)

Set in `.env.production` (gitignored). The Rails app reads them at runtime; Kamal
injects the secrets listed in `config/deploy.yml`.

| Variable | Description |
|---|---|
| `RAILS_MASTER_KEY` | Rails credentials master key (from `config/master.key`) |
| `DATABASE_PASSWORD` | Postgres password (app + `db` accessory) |
| `DEVISE_JWT_SECRET_KEY` | Secret for signing auth tokens |
| `APP_DOMAIN` | Public API origin (e.g. `https://api.hatiwal.51.254.130.18.nip.io`) |
| `ALLOWED_ORIGINS` | Comma-separated allowed CORS origins (optional) |
| `ACTIVE_STORAGE_SERVICE` | `local` (default) or `amazon` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_BUCKET` / `AWS_REGION` | S3 (only if `ACTIVE_STORAGE_SERVICE=amazon`) |

> `DATABASE_HOST/PORT/USERNAME` and `REDIS_URL` are set as **clear** env in
> `config/deploy.yml` (they point at the `hatiwal_api-db` / `hatiwal_api-redis`
> accessories on `hatiwal_api-net`) — no `DATABASE_URL` is used in production.

---

## Troubleshooting

### Container won't start
```bash
kamal app logs
kamal status
```

### Database connection issues
```bash
kamal app exec 'bin/rails db:version'
```

### Migrations pending
```bash
bin/kms migrate
```

### Check running containers
```bash
kamal app exec 'echo OK'
```

---

## Security Checklist

- [ ] SSL certificate active (kamal-proxy handles via Let's Encrypt)
- [ ] `RAILS_MASTER_KEY` not committed to git
- [ ] Strong `DEVISE_JWT_SECRET_KEY` (run: `bin/rails secret`)
- [ ] PostgreSQL password is strong and not in git
- [ ] SSH key-based auth only (no password login on server)
- [ ] Firewall: only ports 22, 80, 443 open
- [ ] Regular database backups configured

---

## Database Backup

```bash
# Download a timestamped dump from production → ./backups/
bin/kms db:dump

# Restore a dump back to PRODUCTION (asks to confirm)
bin/kms db:restore backups/hatiwal_api_YYYYMMDD_HHMMSS.sql

# Load a dump into your LOCAL docker-compose DB (safe — never touches prod)
bin/kms db:load
```

> Backups land in `./backups/` (gitignored). Copy important ones off-machine.
