# Testing Guide

## Overview

The backend uses **RSpec** for all tests. There are no frontend tests.

| Tool | Purpose |
|---|---|
| RSpec | Test framework |
| RSwag | Request specs + Swagger docs |
| FactoryBot | Test data factories |
| Faker | Fake data generation |
| Shoulda Matchers | One-liner model assertions |
| Database Cleaner | Test isolation |
| SimpleCov | Code coverage |

---

## Running Tests

```bash
# Run all specs
bundle exec rspec

# Run only model specs
bundle exec rspec spec/models/

# Run only request specs
bundle exec rspec spec/requests/

# Run only policy specs
bundle exec rspec spec/policies/

# Run only service specs
bundle exec rspec spec/services/

# Run a specific file
bundle exec rspec spec/models/listing_spec.rb

# Run a specific line
bundle exec rspec spec/models/listing_spec.rb:42

# Run with coverage report
COVERAGE=true bundle exec rspec

# Watch mode (re-runs on file change)
bundle exec guard
```

---

## Test Structure

```
spec/
  rails_helper.rb
  swagger_helper.rb
  factories/
    users.rb
    listings.rb
    categories.rb
    listing_images.rb
    conversations.rb
    messages.rb
    saved_listings.rb
    reports.rb
  models/
    user_spec.rb
    listing_spec.rb
    category_spec.rb
    conversation_spec.rb
    message_spec.rb
    saved_listing_spec.rb
    report_spec.rb
  requests/
    api/
      v1/
        auth_spec.rb
        listings_spec.rb
        categories_spec.rb
        conversations_spec.rb
        messages_spec.rb
        saved_listings_spec.rb
        reports_spec.rb
        users/
          profiles_spec.rb
  policies/
    listing_policy_spec.rb
    conversation_policy_spec.rb
    message_policy_spec.rb
    report_policy_spec.rb
  services/
    conversations/
      start_service_spec.rb
    listings/
      search_service_spec.rb
  support/
    auth_helpers.rb
    shared_examples/
```

---

## Writing Tests

### Model Specs

```ruby
# spec/models/listing_spec.rb
require 'rails_helper'

RSpec.describe Listing, type: :model do
  # Associations
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:category) }
    it { should have_many(:listing_images).dependent(:destroy) }
    it { should have_many(:conversations).dependent(:destroy) }
    it { should have_many(:saved_listings).dependent(:destroy) }
  end

  # Validations
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:price) }
    it { should validate_presence_of(:category) }
    it { should validate_numericality_of(:price).is_greater_than(0) }
  end

  # Enums
  describe 'enums' do
    it { should define_enum_for(:status).with_values(draft: 0, active: 1, reserved: 2, sold: 3) }
  end

  # Scopes
  describe 'scopes' do
    describe '.active' do
      it 'returns only active listings' do
        active = create(:listing, status: :active)
        create(:listing, status: :draft)
        create(:listing, status: :sold)
        expect(Listing.active).to contain_exactly(active)
      end
    end

    describe '.ordered' do
      it 'returns listings newest first' do
        old = create(:listing, created_at: 2.days.ago)
        new_one = create(:listing, created_at: 1.hour.ago)
        expect(Listing.ordered).to eq([new_one, old])
      end
    end
  end

  # Instance methods
  describe '#full_location' do
    it 'returns the location string' do
      listing = build(:listing, location: 'Kabul, Afghanistan')
      expect(listing.full_location).to eq('Kabul, Afghanistan')
    end
  end

  # Search
  describe '.search' do
    it 'finds listings by title word' do
      phone = create(:listing, title: 'Samsung Phone', status: :active)
      create(:listing, title: 'Leather Jacket', status: :active)

      expect(Listing.search('samsung')).to contain_exactly(phone)
    end

    it 'supports multi-word search' do
      target = create(:listing, title: 'Samsung Galaxy Phone', status: :active)
      create(:listing, title: 'Samsung Laptop', status: :active)

      expect(Listing.search('samsung galaxy')).to contain_exactly(target)
    end

    it 'returns all listings when query is blank' do
      create_list(:listing, 3, status: :active)
      expect(Listing.search('')).to eq(Listing.all)
    end
  end
end
```

### Factory Example

```ruby
# spec/factories/listings.rb
FactoryBot.define do
  factory :listing do
    association :user
    association :category

    title       { Faker::Commerce.product_name }
    description { Faker::Lorem.paragraph }
    price       { Faker::Commerce.price(range: 100..10_000) }
    currency    { 'AFN' }
    status      { :draft }
    location    { 'Kabul, Afghanistan' }

    trait :active do
      status { :active }
    end

    trait :reserved do
      status { :reserved }
    end

    trait :sold do
      status { :sold }
    end

    trait :with_images do
      after(:create) do |listing|
        create_list(:listing_image, 3, listing: listing)
      end
    end
  end
end
```

### Request Specs (RSwag)

```ruby
# spec/requests/api/v1/listings_spec.rb
require 'swagger_helper'

RSpec.describe 'Api::V1::ListingsController', type: :request do
  path '/api/v1/listings' do
    rswag_prepare_connection(:user)

    get('browse active listings') do
      tags 'Listings'
      description 'Returns paginated active listings for buyers'
      produces 'application/json'

      rswag_auth_from(:user)

      parameter name: :search,      in: :query, type: :string,  required: false, description: 'Search query'
      parameter name: :category_id, in: :query, type: :integer, required: false, description: 'Filter by category'

      response(401, 'unauthorized') do
        let(:"access-token") { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end

      response(200, 'successful') do
        before { create_list(:listing, 3, :active) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['listings']).to be_an(Array)
          expect(data['listings'].length).to eq(3)
          expect(data).to have_key('meta')
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

    post('create a listing') do
      tags 'Listings'
      description 'Create a new listing (starts as draft)'
      consumes 'application/json'
      produces 'application/json'

      rswag_auth_from(:user)

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          listing: {
            type: :object,
            required: [:title, :price, :category_id],
            properties: {
              title:       { type: :string },
              description: { type: :string },
              price:       { type: :number },
              currency:    { type: :string },
              category_id: { type: :integer },
              location:    { type: :string },
              latitude:    { type: :number },
              longitude:   { type: :number }
            }
          }
        }
      }

      response(422, 'unprocessable entity — missing title') do
        let(:body) { { listing: { price: 500, category_id: create(:category).id } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['errors']).to be_present
        end
      end

      response(201, 'created') do
        let(:body) do
          {
            listing: {
              title: 'Samsung Galaxy S24',
              price: 45_000,
              currency: 'AFN',
              category_id: create(:category).id,
              location: 'Kabul, Afghanistan'
            }
          }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data['listing']['title']).to eq('Samsung Galaxy S24')
          expect(data['listing']['status']).to eq('draft')
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

### Policy Specs

```ruby
# spec/policies/listing_policy_spec.rb
require 'rails_helper'

RSpec.describe ListingPolicy, type: :policy do
  subject { described_class }

  let(:owner)    { create(:user) }
  let(:other)    { create(:user) }
  let(:listing)  { create(:listing, :active, user: owner) }

  permissions :index?, :show? do
    it 'allows any authenticated user' do
      expect(subject).to permit(owner, listing)
      expect(subject).to permit(other, listing)
    end
  end

  permissions :create? do
    it 'allows any authenticated user' do
      expect(subject).to permit(other, Listing.new)
    end
  end

  permissions :update?, :destroy? do
    it 'allows the owner' do
      expect(subject).to permit(owner, listing)
    end

    it 'denies other users' do
      expect(subject).not_to permit(other, listing)
    end
  end

  permissions :reserve? do
    it 'allows the owner of an active listing' do
      expect(subject).to permit(owner, listing)
    end

    it 'denies when listing is not active' do
      sold = create(:listing, :sold, user: owner)
      expect(subject).not_to permit(owner, sold)
    end

    it 'denies other users' do
      expect(subject).not_to permit(other, listing)
    end
  end
end
```

### Service Specs

```ruby
# spec/services/conversations/start_service_spec.rb
require 'rails_helper'

RSpec.describe Services::Conversations::StartService do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:listing) { create(:listing, :active, user: seller) }

  subject(:service) do
    described_class.new(buyer: buyer, listing: listing, message_body: 'Is this still available?')
  end

  it 'creates a conversation' do
    expect { service.call }.to change(Conversation, :count).by(1)
  end

  it 'creates the initial message' do
    expect { service.call }.to change(Message, :count).by(1)
  end

  it 'sets buyer and seller correctly' do
    conversation = service.call
    expect(conversation.buyer).to eq(buyer)
    expect(conversation.seller).to eq(seller)
  end

  it 'returns the existing conversation if one already exists' do
    existing = create(:conversation, listing: listing, buyer: buyer, seller: seller)
    result = service.call
    expect(result).to eq(existing)
    expect(Conversation.count).to eq(1)
  end
end
```

---

## Auth Helper

```ruby
# spec/support/auth_helpers.rb
module AuthHelpers
  def auth_headers_for(user)
    post '/api/v1/auth/sign_in', params: { email: user.email, password: user.password }
    {
      'access-token' => response.headers['access-token'],
      'token-type'   => response.headers['token-type'],
      'client'       => response.headers['client'],
      'uid'          => response.headers['uid']
    }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
```

---

## Best Practices

- **Isolation**: Each spec is independent — use FactoryBot, not fixtures
- **AAA pattern**: Arrange → Act → Assert
- **Descriptive names**: `it 'denies non-owners from editing another user's listing'`
- **Test edge cases**: nil inputs, empty search, unauthorized access, state transitions
- **Don't over-mock**: Hit the real database in request and model specs
- **One assertion per `it` block** when possible — easier to diagnose failures
- **Traits over multiple factories**: Use `create(:listing, :active)` not `create(:active_listing)`

---

## Generating Swagger Docs

```bash
bundle exec rake rswag:specs:swaggerize
```

Output is saved to `swagger/v1/swagger.yaml`. View at `http://localhost:3000/api-docs` when the server is running.

---

## Coverage

```bash
COVERAGE=true bundle exec rspec
open coverage/index.html
```

Target: **90%+ coverage** on models, policies, and request specs.
