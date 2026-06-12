# Deployment Guide

## Overview

Hatiwal API is deployed using **Kamal 2** for zero-downtime deployments to a VPS.

---

## Architecture

```
Internet
    ↓
kamal-proxy (SSL termination, port 80/443)
    ↓
hatiwal-api (Rails API, port 3000)
    ↓
PostgreSQL + Redis (accessories, same VPS)
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

```yaml
service: hatiwal-api
image: your-dockerhub-username/hatiwal-api

servers:
  web:
    - YOUR_SERVER_IP

proxy:
  ssl: true
  host: api.hatiwal.com
  app_port: 3000

registry:
  username: your-dockerhub-username
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_ENV: production
    RAILS_LOG_TO_STDOUT: true
    RAILS_SERVE_STATIC_FILES: true
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - REDIS_URL
    - DEVISE_JWT_SECRET_KEY

volumes:
  - hatiwal_storage:/rails/storage

builder:
  arch: amd64

accessories:
  db:
    image: postgres:15
    host: YOUR_SERVER_IP
    port: 5432
    env:
      clear:
        POSTGRES_DB: hatiwal_production
      secret:
        - POSTGRES_PASSWORD
    volumes:
      - hatiwal_db:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    host: YOUR_SERVER_IP
    port: 6379
    volumes:
      - hatiwal_redis:/data
```

### `.kamal/secrets`

```bash
KAMAL_REGISTRY_PASSWORD=$(cat .env.production | grep KAMAL_REGISTRY_PASSWORD | cut -d= -f2)
RAILS_MASTER_KEY=$(cat config/master.key)
DATABASE_URL=$(cat .env.production | grep DATABASE_URL | cut -d= -f2)
REDIS_URL=$(cat .env.production | grep REDIS_URL | cut -d= -f2)
DEVISE_JWT_SECRET_KEY=$(cat .env.production | grep DEVISE_JWT_SECRET_KEY | cut -d= -f2)
POSTGRES_PASSWORD=$(cat .env.production | grep POSTGRES_PASSWORD | cut -d= -f2)
```

---

## Deploying

### First-time Setup

```bash
# Setup server (installs Docker, creates directories)
kamal setup

# Run database migrations
kamal app exec 'bin/rails db:migrate'

# Seed categories
kamal app exec 'bin/rails db:seed'
```

### Regular Deploys

```bash
# Deploy latest code
kamal deploy

# Check status
kamal status

# View logs
kamal logs

# Rollback to previous version
kamal rollback
```

---

## KMS (Kamal Management Script)

Add this script as `bin/kms` for common operations:

```bash
#!/usr/bin/env bash
# bin/kms — Kamal management shortcuts

case "$1" in
  # Deployment
  deploy)       kamal deploy ;;
  rollback)     kamal rollback ;;
  status)       kamal status ;;
  restart)      kamal app restart ;;

  # Rails commands
  console)      kamal app exec --interactive 'bin/rails console' ;;
  migrate)      kamal app exec 'bin/rails db:migrate' ;;
  rollback-db)  kamal app exec 'bin/rails db:rollback' ;;
  seed)         kamal app exec 'bin/rails db:seed' ;;
  routes)       kamal app exec 'bin/rails routes' ;;

  # Logs
  logs)         kamal logs ;;
  logs-f)       kamal logs --follow ;;
  logs-n)       kamal logs --lines="${2:-50}" ;;

  # Database
  db-console)   kamal accessory exec db --interactive 'psql -U postgres hatiwal_production' ;;

  # App shell
  bash)         kamal app exec --interactive 'bash' ;;

  *)
    echo "Usage: bin/kms <command>"
    echo ""
    echo "Commands:"
    echo "  deploy, rollback, status, restart"
    echo "  console, migrate, rollback-db, seed, routes"
    echo "  logs, logs-f, logs-n <lines>"
    echo "  db-console, bash"
    ;;
esac
```

```bash
chmod +x bin/kms
```

---

## Environment Variables (Production)

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection string |
| `RAILS_MASTER_KEY` | Rails credentials master key |
| `DEVISE_JWT_SECRET_KEY` | Secret for signing auth tokens |
| `ALLOWED_ORIGINS` | Comma-separated allowed CORS origins |
| `ACTIVE_STORAGE_SERVICE` | `local` or `amazon` |
| `AWS_ACCESS_KEY_ID` | S3 credentials (if using S3) |
| `AWS_SECRET_ACCESS_KEY` | S3 credentials (if using S3) |
| `AWS_BUCKET` | S3 bucket name |
| `AWS_REGION` | S3 region |

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
# Dump production database
bin/kms db-console
# Then: \copy ... or use pg_dump via kamal exec

# Or directly
kamal accessory exec db 'pg_dump -U postgres hatiwal_production' > backup.sql
```
