# hatiwal-api — Claude Instructions

## Testing Convention

**"test" always means backend RSpec** — never frontend.

When asked to write or check tests, always write:
- `spec/requests/` — RSwag request specs for controllers
- `spec/models/` — RSpec model specs
- `spec/policies/` — Pundit policy specs
- `spec/services/` — Service object specs

The mobile app has no automated tests. Never look for or create frontend/mobile test files unless explicitly asked.

---

## Prompt Library

**Read the relevant file before starting any task.** These are the authoritative implementation guides — they define the patterns, file structure, and rules this project enforces.

| File | Covers |
|---|---|
| [docs/prompts/backend.prompt.md](docs/prompts/backend.prompt.md) | Core backend rules — migrations, models, controllers, serializers, policies, services |

---

## Other Docs

| File | Covers |
|---|---|
| [README.md](README.md) | Local dev setup, env vars, running the app |
| [docs/TESTING.md](docs/TESTING.md) | Testing conventions and how to run specs |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Deployment process |

---

## Slash Commands (Skills)

| Command | Reads | What it does |
|---------|-------|-------------|
| `/backend <description>` | `backend.prompt.md` | Implement any backend feature — migration, model, policy, serializer, controller, routes |

---

## Quick Rules Reminder

- **Always** read `docs/prompts/backend.prompt.md` before implementing anything non-trivial
- **Never** use `render json:` in controllers — use `paginate_blue` / `render_blue` / `render_unprocessable_entity`
- **Always** run RuboCop on every modified Ruby file before finishing
- **Always** use `authorize(record)` — never pass `policy_class:` explicitly
- **Always** use `class_name: Model.name` (not string) for associations
- **Always** use `policy_scope` for index/list queries
- **Always** add FactoryBot factory for every new model
- **Always** add RSwag tests for every new controller
- Use symbols and constants — never hardcoded strings for types/enums
- Business logic belongs in models and service objects — controllers stay thin

---

## Domain Context

This is the API backend for **Hatiwal**, a local marketplace app for Afghanistan.

Key domain concepts:
- **User** — one account for both buyer and seller. Has `buyer_mode` and `seller_mode` available.
- **Listing** — item for sale. States: `draft`, `active`, `reserved`, `sold`.
- **Category** — marketplace categories. Seeded, not user-created.
- **Conversation** — chat thread tied to a Listing between a buyer (initiator) and the listing's seller.
- **Message** — a single message in a conversation.
- **Report** — user-submitted complaint against a listing or user.
- **SavedListing** — a user bookmarking a listing.

No online payment. No delivery. No web frontend. Pure JSON API for the mobile app only.

---

## API Namespace

All routes are under `/api/v1/`:

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    # auth routes (devise_token_auth)
    # listings
    # categories
    # conversations + messages
    # saved_listings
    # reports
    # users (profiles)
  end
end
```

## Auth

Uses `devise_token_auth`. Token sent in headers:
- `access-token`
- `token-type`
- `client`
- `uid`

Base controller: `Api::V1::BaseController < ApplicationController`
- Includes `DeviseTokenAuth::Concerns::SetUserByToken`
- Includes `Pundit::Authorization`
- `before_action :authenticate_user!`

---

## Serializer Pattern

Use `Blueprinter` or a custom `ApplicationSerializer`. Follow the same view pattern as edu-safi:

```ruby
class ListingSerializer < ApplicationSerializer
  fields :id, :title, :price, :status, :created_at

  view :list do
    fields :category_id, :location, :thumbnail_url
  end

  view :detailed do
    fields :description, :category_id, :location, :latitude, :longitude,
           :status, :views_count, :images
  end
end
```

## Response Helpers

Defined in `ApplicationController` or a concern:

```ruby
# Paginated list
paginate_blue(ListingSerializer, @listings, extra: { view: :list })

# Single resource
render_blue(ListingSerializer, @listing, view: :detailed)

# Errors
render_unprocessable_entity(@listing)
render_not_found
```
