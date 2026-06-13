# Backend Development Rules

When you add **migration files**, you **must** follow all the rules below. These are mandatory. Do **not** skip any step.

---

## Core Principles

### 1. Fat Models, Skinny Controllers

**CRITICAL RULE**: Never put business logic in controllers. All logic should be in models and service objects, and data formatting should be in serializers.

**The Flow:**
1. **Controller** → calls model methods or service objects (minimal logic, just orchestration)
2. **Model** → contains business logic, queries, scopes, validations
3. **Service** → handles multi-step operations that span models
4. **Serializer** → calls model methods for computed fields, formats data for JSON
5. **Controller** → uses `paginate_blue` or `render_blue` with serializer

**Examples:**

❌ **BAD — Logic in controller:**

```ruby
# Don't do this
def index
  @listings = Listing.where(status: :active)
    .where("title ILIKE ?", "%#{params[:search]}%")
    .where(category_id: params[:category_id])
    .order(created_at: :desc)
    .page(params[:page])

  render json: @listings.map { |l| { id: l.id, title: l.title, price: l.price } }
end
```

✅ **GOOD — Logic in model, serializer formats:**

```ruby
# Controller — just orchestration
def index
  listings = policy_scope(Listing.active)
  listings = listings.search(params[:search]) if params[:search].present?
  listings = listings.by_category(params[:category_id]) if params[:category_id].present?
  listings = listings.ordered

  paginate_blue(ListingSerializer, listings, extra: { view: :list })
end

# Model — scopes and business logic
class Listing < ApplicationRecord
  scope :active,       -> { where(status: :active) }
  scope :ordered,      -> { order(created_at: :desc) }
  scope :by_category,  ->(id) { where(category_id: id) }

  def self.search(query)
    return all if query.blank?
    words = query.strip.split(/\s+/)
    result = all
    words.each do |word|
      term = "%#{word.downcase}%"
      result = result.where("LOWER(title) LIKE ? OR LOWER(description) LIKE ?", term, term)
    end
    result
  end
end

# Serializer — data formatting
class ListingSerializer < ApplicationSerializer
  fields :id, :title, :price, :status, :created_at

  view :list do
    fields :category_id, :location, :thumbnail_url, :views_count
    field(:seller) { |l| { id: l.user_id, name: l.user.full_name } }
  end
end
```

**Benefits:**
- **Testable**: Model scopes and service logic can be unit tested easily
- **Reusable**: Same scopes used across controllers
- **Clear separation**: Controllers route, models compute, serializers format

---

### 2. Use Direct Class Syntax, Not Module Nesting

**CRITICAL RULE**: Always use direct class syntax with `::` instead of nested module blocks.

**Examples:**

❌ **BAD — Using nested modules:**

```ruby
# Don't do this
module Api
  module V1
    class ListingsController < BaseController
    end
  end
end
```

✅ **GOOD — Using direct class syntax:**

```ruby
# Do this instead
class Api::V1::ListingsController < Api::V1::BaseController
end
```

**Benefits:**
- Cleaner code, less indentation
- Class name immediately visible at the top
- Matches Rails autoloading expectations

---

### 3. Use Symbols and Constants Instead of Strings

**CRITICAL RULE**: Never use hardcoded strings when symbols or constants can be used instead.

**Examples:**

❌ **BAD:**

```ruby
listing.update(status: 'active')
if user.role == 'seller'
```

✅ **GOOD:**

```ruby
listing.update(status: :active)
if user.role == :seller  # or use the enum predicate: user.seller?
```

**Enum definitions:**

```ruby
class Listing < ApplicationRecord
  enum :status, { draft: 0, active: 1, reserved: 2, sold: 3 }
end

# Then use:
listing.active!
listing.active?
Listing.active  # scope
```

**When strings ARE acceptable:**
- User-facing messages (but put them in I18n)
- External API responses
- Database values that are genuinely free-form text

---

### 4. Multi-Word Search Pattern

**CRITICAL RULE**: When searching by name or text, always support multi-word queries. Each word must match, and each word can match any searchable field.

**Why?** Users search for "leather shoes" or "samsung phone" — each word should narrow the results.

❌ **BAD:**

```ruby
listings.where("title ILIKE ?", "%#{params[:search]}%")
```

✅ **GOOD:**

```ruby
def self.search(query)
  return all if query.blank?

  words = query.to_s.strip.split(/\s+/)
  result = all

  words.each do |word|
    term = "%#{word.downcase}%"
    result = result.where(
      "LOWER(title) LIKE ? OR LOWER(description) LIKE ?",
      term, term
    )
  end

  result
end
```

**For user name search (firstname/lastname):**

```ruby
def self.search_by_name(query)
  return all if query.blank?

  words = query.to_s.strip.split(/\s+/)
  result = all

  words.each do |word|
    term = "%#{word.downcase}%"
    result = result.where(
      "LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ?",
      term, term
    )
  end

  result
end
```

---

## Mandatory Development Steps

1. **Add `factory_bot` factories** for every new model — always.

2. **Add the model** with validations, enums, scopes, and associations.

3. **Add serializers** for every new model.

   ```ruby
   class ListingSerializer < ApplicationSerializer
     fields :id, :title, :price, :status

     view :list do
       fields :category_id, :location, :thumbnail_url, :created_at
       field(:seller_name) { |l| l.user.full_name }
     end

     view :detailed do
       fields :description, :category_id, :location, :latitude, :longitude,
              :status, :views_count, :created_at, :updated_at
       field(:images) { |l| l.images.map(&:url) }
       field(:seller) { |l| { id: l.user_id, name: l.user.full_name, phone: l.user.phone } }
       field(:category) { |l| { id: l.category_id, name: l.category.name } }
     end
   end
   ```

4. **Add tests** for every model and controller.

   **Model spec:**
   ```ruby
   require 'rails_helper'

   RSpec.describe Listing, type: :model do
     describe 'validations' do
       it { should validate_presence_of(:title) }
       it { should validate_presence_of(:price) }
     end

     describe 'associations' do
       it { should belong_to(:user) }
       it { should belong_to(:category) }
       it { should have_many(:listing_images).dependent(:destroy) }
     end

     describe 'scopes' do
       describe '.active' do
         it 'returns only active listings' do
           active = create(:listing, status: :active)
           create(:listing, status: :draft)
           expect(Listing.active).to contain_exactly(active)
         end
       end
     end
   end
   ```

   **RSwag controller spec:**
   ```ruby
   require 'swagger_helper'

   RSpec.describe 'Api::V1::ListingsController', type: :request do
     path '/api/v1/listings' do
       rswag_prepare_connection(:user)

       get('list active listings') do
         tags 'Listings'
         description 'Returns paginated active listings visible to buyers'

         rswag_auth_from(:user)
         parameter name: :search, in: :query, type: :string, required: false
         parameter name: :category_id, in: :query, type: :integer, required: false

         response(401, 'unauthorized') do
           let(:"access-token") { nil }
           run_test! do |response|
             expect(response).to have_http_status(:unauthorized)
           end
         end

         response(200, 'successful') do
           run_test! do |response|
             data = JSON.parse(response.body)
             expect(data['listings']).to be_an(Array)
           end

           after do |example|
             example.metadata[:response][:content] = {
               'application/json' => {
                 example: JSON.parse(response.body, symbolize_names: true)
               }
             }
           end
         end
       end
     end
   end
   ```

5. **Add Pundit policies** for every new controller — always.

   ```ruby
   class ListingPolicy < ApplicationPolicy
     def index?
       true  # any authenticated user can browse
     end

     def show?
       true
     end

     def create?
       true  # any user can create a listing
     end

     def update?
       record.user == user
     end

     def destroy?
       record.user == user
     end

     def publish?
       record.user == user && record.draft?
     end

     def reserve?
       record.user == user && record.active?
     end

     def sold?
       record.user == user && record.reserved?
     end

     class Scope < ApplicationPolicy::Scope
       def resolve
         scope.all
       end
     end
   end
   ```

6. **Ensure proper error handling and validation** in controllers.

7. For `index` actions, **use `paginate_blue`**:

   ```ruby
   paginate_blue(
     ListingSerializer,
     @listings,
     extra: { view: :list }
   )
   ```

8. For non-index actions, **use `render_blue`**:

   ```ruby
   render_blue(
     ListingSerializer,
     @listing,
     view: :detailed
   )
   ```

9. **Error handling**:

   ```ruby
   render_unprocessable_entity(@listing)   # validation errors
   render_not_found                         # 404
   ```

10. **Add routes** in `config/routes.rb` whenever you add a controller.

11. **Respect RuboCop** — always run `bundle exec rubocop` before finishing.

12. For list queries, **always use `policy_scope`**:

---

## ⛔ Pre-Commit Checklist (MANDATORY — never skip)

**Before every `git commit` on the backend, all three must pass:**

```bash
# 1. All specs green — zero failures
bundle exec rspec

# 2. No RuboCop offenses
bundle exec rubocop

# 3. Swagger docs regenerated if request specs changed
bundle exec rake rswag:specs:swaggerize
```

**What tests to write / update:**

| What you changed | Tests required |
|---|---|
| New model | `spec/models/<model>_spec.rb` — validations, associations, scopes, methods |
| New controller action | `spec/requests/api/v1/<controller>_spec.rb` — happy path + auth + error cases |
| Changed policy | `spec/policies/<model>_policy_spec.rb` |
| Changed service | `spec/services/<service>_spec.rb` |
| Changed serializer | Add or update the relevant request spec to assert the new fields in the JSON response |

**Never:**
- Commit with a failing spec
- Comment out or skip a failing spec without fixing the root cause
- Commit without running `bundle exec rspec` first

    ```ruby
    listings = policy_scope(Listing.active)
    ```

---

## Service Objects

Use service objects for multi-step operations that span multiple models or have side effects.

**When to use a service:**
- Creating a listing and processing images in one step
- Starting a conversation (create Conversation + first Message + notify seller)
- Marking a listing as sold (update listing + close other conversations)

**Naming:** `Services::Listings::CreateService`, `Services::Conversations::StartService`

**Pattern:**

```ruby
class Services::Conversations::StartService
  def initialize(buyer:, listing:, message_body:)
    @buyer = buyer
    @listing = listing
    @message_body = message_body
  end

  def call
    return existing_conversation if existing_conversation

    ActiveRecord::Base.transaction do
      conversation = Conversation.create!(
        listing: @listing,
        buyer: @buyer,
        seller: @listing.user
      )
      conversation.messages.create!(
        user: @buyer,
        body: @message_body
      )
      conversation
    end
  end

  private

  def existing_conversation
    @existing_conversation ||= Conversation.find_by(
      listing: @listing,
      buyer: @buyer
    )
  end
end

# In controller:
def create
  service = Services::Conversations::StartService.new(
    buyer: current_user,
    listing: @listing,
    message_body: params[:message]
  )

  conversation = service.call

  render_blue(ConversationSerializer, conversation, view: :detailed)
rescue ActiveRecord::RecordInvalid => e
  render_unprocessable_entity(e.record)
end
```

---

## Full Controller Example

```ruby
class Api::V1::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [:show, :update, :destroy, :publish, :reserve, :sold]

  def index
    listings = policy_scope(Listing.active).ordered
    listings = listings.search(params[:search]) if params[:search].present?
    listings = listings.by_category(params[:category_id]) if params[:category_id].present?

    paginate_blue(ListingSerializer, listings, extra: { view: :list })
  end

  def show
    @listing.increment!(:views_count)
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def create
    @listing = current_user.listings.new(listing_params)
    authorize @listing

    if @listing.save
      render_blue(ListingSerializer, @listing, view: :detailed, status: :created)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def update
    authorize @listing

    if @listing.update(listing_params)
      render_blue(ListingSerializer, @listing, view: :detailed)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def destroy
    authorize @listing

    if @listing.destroy
      head :no_content
    else
      render_unprocessable_entity(@listing)
    end
  end

  def publish
    authorize @listing, :publish?
    @listing.active!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def reserve
    authorize @listing, :reserve?
    @listing.reserved!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  def sold
    authorize @listing, :sold?
    @listing.sold!
    render_blue(ListingSerializer, @listing, view: :detailed)
  end

  private

  def set_listing
    @listing = policy_scope(Listing).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  def listing_params
    params.require(:listing).permit(
      :title, :description, :price, :category_id,
      :location, :latitude, :longitude, :currency
    )
  end
end
```

---

## My Listings (Seller View)

Seller endpoints for managing their own listings:

```ruby
class Api::V1::My::ListingsController < Api::V1::BaseController
  before_action :set_listing, only: [:show, :update, :destroy, :publish, :reserve, :sold]

  def index
    listings = policy_scope(current_user.listings).ordered
    paginate_blue(ListingSerializer, listings, extra: { view: :seller_list })
  end

  # ... rest of actions
end
```

---

## Conversation & Messaging Rules

- A `Conversation` is always between two users about a specific `Listing`.
- A buyer can only start one conversation per listing (prevent duplicates — check in service).
- The listing's seller cannot start a conversation on their own listing.
- Messages are ordered by `created_at ASC`.
- Real-time delivery via Action Cable (chat channel).

---

## Authorization Rules

- Any authenticated user can **browse** listings.
- Only the listing owner can **edit**, **delete**, **publish**, **reserve**, or **mark sold**.
- Any authenticated user can **start a conversation** on an active listing they do not own.
- Only conversation participants can **read or send messages** in that conversation.
- Any user can **save** any active listing.
- Any user can **report** any listing or user (except themselves).

---

## How to Use This Prompt

This file is the authoritative checklist Claude must follow for backend development. Whenever asked to add or modify:

- Any new table / model / migration / controller / endpoint

Read this file first and apply all rules. Provide a short "task brief" each time; if details are missing, proceed with minimal reasonable assumptions and note them.

### Task Brief Template

```
Feature: <short title>
Type: <new table/model | new endpoint | both>
Route(s): </api/v1/...>
Entity/Model: <name> with fields <...>
Notes: special behaviors, policies, or validations
```

---

## RuboCop

Always ensure your code passes RuboCop:

```bash
bundle exec rubocop
bundle exec rubocop -a  # auto-fix safe offenses
```

## Testing

```bash
# Run all specs
bundle exec rspec

# Run only request specs
bundle exec rspec spec/requests/

# Run model specs
bundle exec rspec spec/models/

# Generate Swagger docs
bundle exec rake rswag:specs:swaggerize
```
