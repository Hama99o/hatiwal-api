# Hatiwal API

Ruby on Rails JSON API backend for the Hatiwal local marketplace app.

---

## Tech Stack

- **Ruby on Rails 8.1** (API mode) — pure JSON API, no web frontend
- **PostgreSQL 16** — primary database
- **Redis 7** — caching and Action Cable (chat)
- **Devise Token Auth** — JWT-based authentication via headers
- **Pundit** — authorization policies
- **Blueprinter** — response serialization with views
- **Pagy** — pagination
- **Active Storage** — listing photo uploads
- **RSpec + RSwag** — tests + Swagger docs
- **FactoryBot + Faker** — test data
- **RuboCop** — code style enforcement
- **Kamal 2** — production deployment

---

## Quick Start

### Prerequisites

- Ruby 3.4.8
- PostgreSQL 16+
- Redis 7+

### Installation

```bash
cd hatiwal-api

bundle install

cp .env.example .env
# Edit .env with your database credentials

bin/rails db:create db:migrate db:seed

bin/rails server
```

API runs at `http://localhost:3000`.

### Docker

```bash
docker compose up
```

- API: `http://localhost:3000`
- Swagger: `http://localhost:3000/api-docs`
- PostgreSQL: port `5432`
- Redis: port `6379`

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | `postgres://hatiwal:password@localhost:5432/hatiwal_development` | PostgreSQL connection |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection |
| `DEVISE_JWT_SECRET_KEY` | — | Secret for token signing |
| `ALLOWED_ORIGINS` | `*` | CORS allowed origins |

---

## Demo Credentials

| Role | Email | Password |
|---|---|---|
| Buyer / Seller | `demo@hatiwal.com` | `demo1234` |
| Second User | `seller@hatiwal.com` | `seller1234` |

---

## Project Structure

```
app/
  controllers/api/v1/     ← All API controllers
    base_controller.rb
    listings_controller.rb
    categories_controller.rb
    conversations_controller.rb
    messages_controller.rb
    reports_controller.rb
    my/                   ← Seller (owner) controllers
    users/                ← Profile controllers
  models/
  policies/               ← Pundit policies
  serializers/            ← Blueprinter serializers
  services/               ← Business logic service objects
config/
  routes.rb
  deploy.yml              ← Kamal production config
db/
  migrate/
  seeds.rb
spec/
  requests/               ← RSwag controller tests
  models/
  policies/
  services/
  factories/
  support/
```

---

## Scripts

```bash
bundle exec rspec                          # Run all tests
COVERAGE=true bundle exec rspec            # With coverage
bundle exec rake rswag:specs:swaggerize    # Generate Swagger docs
bundle exec rubocop                        # Code style check
bundle exec rubocop -a                     # Auto-fix
bin/rails console                          # Rails console
bin/rails db:migrate                       # Run migrations
bin/rails db:seed                          # Seed data
```

---

## API Overview

Base URL: `/api/v1`

Auth headers: `access-token`, `token-type`, `client`, `uid`

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/auth/sign_in` | Login |
| `POST` | `/api/v1/auth/sign_up` | Register |
| `DELETE` | `/api/v1/auth/sign_out` | Logout |
| `GET` | `/api/v1/listings` | Browse listings (buyer) |
| `GET` | `/api/v1/listings/:id` | Listing detail |
| `POST` | `/api/v1/listings/:id/save` | Save listing |
| `DELETE` | `/api/v1/listings/:id/unsave` | Unsave listing |
| `POST` | `/api/v1/listings/:id/conversations` | Start chat |
| `GET` | `/api/v1/categories` | All categories |
| `GET` | `/api/v1/conversations` | My conversations |
| `GET` | `/api/v1/conversations/:id` | Conversation detail |
| `GET` | `/api/v1/conversations/:id/messages` | Messages |
| `POST` | `/api/v1/conversations/:id/messages` | Send message |
| `POST` | `/api/v1/reports` | Report a listing or user |
| `GET` | `/api/v1/users/me` | My profile |
| `PUT` | `/api/v1/users/me` | Update my profile |
| `GET` | `/api/v1/users/:id` | Public profile |
| `GET` | `/api/v1/my/listings` | My listings (seller) |
| `POST` | `/api/v1/my/listings` | Create listing |
| `PUT` | `/api/v1/my/listings/:id` | Update listing |
| `DELETE` | `/api/v1/my/listings/:id` | Delete listing |
| `PUT` | `/api/v1/my/listings/:id/publish` | Publish draft |
| `PUT` | `/api/v1/my/listings/:id/reserve` | Mark reserved |
| `PUT` | `/api/v1/my/listings/:id/sold` | Mark sold |
| `GET` | `/api/v1/my/saved_listings` | My saved listings |

---

## Deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for Kamal setup and production deployment.

```bash
# First deploy
kamal setup && kamal deploy
bin/kms migrate
bin/kms seed

# Regular deploy
kamal deploy

# Or use the kms script
bin/kms deploy
bin/kms logs-f
bin/kms console
```
