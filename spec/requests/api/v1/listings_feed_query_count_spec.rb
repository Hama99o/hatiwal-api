require "rails_helper"

# TASK-API-FEEDN1 — the public feed's query count must not grow with the number
# of cards on the page.
#
# WHY THIS SHAPE OF ASSERTION, and not a fixed number:
#
# `expect(queries).to eq(14)` proves nothing about an N+1. It passes on a
# 1-row page whether or not the code is O(N), and it fails on every unrelated
# refactor that adds or removes one query — so it gets "fixed" by editing the
# constant, which is how an N+1 walks back in under a green suite. The only
# assertion that pins the bug is the SLOPE: render a small page and a large
# page and require the same count. If any association is read per-row, the
# large page costs ~4x more queries and the spec fails by a wide margin.
#
# What the feed's :list view actually reads per card, all of which used to be
# unloaded before this fix (the controller preloaded price_histories and
# sale_transactions only):
#   field(:seller)        -> l.user, then u.avatar.attached? / u.avatar.url
#   field(:category)      -> l.category
#   field(:thumbnail_url) -> images attachment + blob (+ variant records)
#   field(:image_urls)    -> the same attachments again
#
# So every listing is given its OWN seller (with an avatar), its OWN category,
# its OWN images and its OWN price history — otherwise Rails' per-request
# identity map would hide the very N+1 this measures behind a shared row.
#
# Measured on this spec, 3 cards -> 15 cards:
#   before the fix   guest 25 -> 109   signed in 32 -> 116   (+7 per card)
#   after the fix    guest 10 ->  10   signed in 17 ->  17   (flat)
RSpec.describe "Api::V1::ListingsController feed query count", type: :request do
  # Only the SQL the request itself issues counts. SAVEPOINTs come from the
  # transactional-fixtures wrapper, and devise_token_auth rewrites the user's
  # token on every authenticated request — neither scales with page size, and
  # both would add noise to a strict equality assertion.
  def count_queries
    count = 0
    subscriber = lambda do |*, payload|
      sql = payload[:sql].to_s
      next if sql.start_with?("SAVEPOINT", "RELEASE SAVEPOINT", "ROLLBACK TO SAVEPOINT")
      next if sql.match?(/\AUPDATE "users" SET "tokens"/)

      count += 1
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    count
  end

  # One fully-populated feed card: distinct seller (+avatar), distinct category,
  # a real attached image, and a price history row.
  def build_feed_card
    seller = create(:user)
    seller.avatar.attach(
      io:           File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
      filename:     "avatar.jpg",
      content_type: "image/jpeg"
    )
    listing = create(:listing, :active, :with_image, user: seller, category: create(:category))
    create(:listing_price_history, :recent_drop, listing: listing)
    listing
  end

  def create_feed_cards(count)
    Array.new(count) { build_feed_card }
  end

  describe "GET /api/v1/listings (guest)" do
    it "issues the same number of queries for a 15-card page as for a 3-card page" do
      create_feed_cards(3)

      # Warm-up: the very first request in the example loads the schema cache and
      # Pundit/serializer constants, which would inflate the baseline only.
      get "/api/v1/listings", as: :json
      expect(response).to have_http_status(:ok)

      small_page = count_queries { get "/api/v1/listings", as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      create_feed_cards(12) # 15 total — still one page (Pagy default limit is 20)

      large_page = count_queries { get "/api/v1/listings", as: :json }
      body = JSON.parse(response.body)
      expect(body["listings"].size).to eq(15)

      # Not vacuous: every card really does carry the four fields whose
      # associations this spec is about.
      row = body["listings"].first
      expect(row["seller"]["avatar_url"]).to be_present
      expect(row["category"]).to be_present
      expect(row["thumbnail_url"]).to be_present
      expect(row["image_urls"]).to be_present
      expect(row["price_drop_percent"]).to eq(20)

      expect(large_page).to eq(small_page),
        "Feed query count must not grow with page size (N+1): " \
        "#{small_page} queries for 3 cards, #{large_page} for 15"
    end
  end

  describe "GET /api/v1/listings (signed in)" do
    let(:viewer)  { create(:user) }
    let(:headers) { auth_headers_for(viewer) }

    # The signed-in path adds viewed_ids/saved_ids (two flat IN-subquery
    # lookups) and the blocked-pair policy scope. Those are per-REQUEST, not
    # per-row, so the slope must still be flat.
    it "issues the same number of queries for a 15-card page as for a 3-card page" do
      cards = create_feed_cards(3)
      cards.each { |l| create(:saved_listing, user: viewer, listing: l) }

      get "/api/v1/listings", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      small_page = count_queries { get "/api/v1/listings", headers: headers, as: :json }

      more = create_feed_cards(12)
      more.each { |l| create(:saved_listing, user: viewer, listing: l) }

      large_page = count_queries { get "/api/v1/listings", headers: headers, as: :json }
      body = JSON.parse(response.body)
      expect(body["listings"].size).to eq(15)
      expect(body["listings"].map { |l| l["is_saved"] }).to all(be(true))

      expect(large_page).to eq(small_page),
        "Feed query count must not grow with page size (N+1): " \
        "#{small_page} queries for 3 cards, #{large_page} for 15"
    end
  end

  # SF-B10 lives next door: a hold is what puts `held_units` on a feed card, and
  # `held_units` reads `sale_transactions`. Holds must not add a query per row
  # either — this is the row-count version of the assertion SF-B2's own spec
  # could only make as "same rows, holds added", because before this fix the
  # feed's row-scaling was already broken.
  describe "GET /api/v1/listings with a hold on every card" do
    it "issues the same number of queries for 15 held cards as for 3" do
      buyer = create(:user)

      hold = lambda do |listing|
        create(:conversation, listing: listing, buyer: buyer, seller: listing.user)
        listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: 2)
      end

      first_batch = create_feed_cards(3)
      first_batch.each { |l| l.update!(quantity: 5) }
      first_batch.each(&hold)

      get "/api/v1/listings", as: :json
      small_page = count_queries { get "/api/v1/listings", as: :json }

      second_batch = create_feed_cards(12)
      second_batch.each { |l| l.update!(quantity: 5) }
      second_batch.each(&hold)

      large_page = count_queries { get "/api/v1/listings", as: :json }
      body = JSON.parse(response.body)
      expect(body["listings"].size).to eq(15)
      expect(body["listings"].map { |l| l["held_units"] }).to all(eq(2))

      expect(large_page).to eq(small_page),
        "held_units must not cost a query per held row (N+1): " \
        "#{small_page} queries for 3 held cards, #{large_page} for 15"
    end
  end

  # TASK-API-FEEDN1, second half of the card: "then check every OTHER endpoint
  # rendering the :list or :seller_list view for the same gap".
  #
  # All five of these already carried the correct include list before this
  # ticket (the feed was the odd one out), so this block is a REGRESSION LOCK,
  # not a fix — an endpoint that renders :list without preloading what :list
  # reads is not a local performance choice, it is the same bug in a different
  # file, and there was nothing stopping the next one from shipping.
  #
  # One flat-slope assertion per endpoint, same method as the feed above.
  describe "every other endpoint rendering :list / :seller_list" do
    let(:owner)   { create(:user) }
    let(:headers) { auth_headers_for(owner) }

    it "GET /api/v1/listings/:id/similar — flat slope" do
      category = create(:category)
      source   = create(:listing, :active, :with_image, category: category)
      3.times { build_feed_card.update!(category: category) }

      get "/api/v1/listings/#{source.id}/similar", as: :json
      small_page = count_queries { get "/api/v1/listings/#{source.id}/similar", as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      # The rail is capped at 8 (Listing.similar_to), so 8 is its full page.
      5.times { build_feed_card.update!(category: category) }
      large_page = count_queries { get "/api/v1/listings/#{source.id}/similar", as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(8)

      expect(large_page).to eq(small_page),
        "similar rail: #{small_page} queries for 3 rows, #{large_page} for 8"
    end

    it "GET /api/v1/my/listings (:seller_list) — flat slope" do
      # :seller_list has NO `seller` field, so `user` is deliberately not
      # preloaded there; it DOES read conversations_count and the owner-only
      # `sale` block (buyer + buyer avatar), which the controller preloads.
      3.times { build_feed_card.update!(user: owner) }
      get "/api/v1/my/listings", headers: headers, as: :json

      small_page = count_queries { get "/api/v1/my/listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      12.times { build_feed_card.update!(user: owner) }
      large_page = count_queries { get "/api/v1/my/listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(15)

      expect(large_page).to eq(small_page),
        "my/listings: #{small_page} queries for 3 rows, #{large_page} for 15"
    end

    it "GET /api/v1/my/saved_listings — flat slope" do
      3.times { create(:saved_listing, user: owner, listing: build_feed_card) }
      get "/api/v1/my/saved_listings", headers: headers, as: :json

      small_page = count_queries { get "/api/v1/my/saved_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      12.times { create(:saved_listing, user: owner, listing: build_feed_card) }
      large_page = count_queries { get "/api/v1/my/saved_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(15)

      expect(large_page).to eq(small_page),
        "my/saved_listings: #{small_page} queries for 3 rows, #{large_page} for 15"
    end

    it "GET /api/v1/my/viewed_listings — flat slope" do
      3.times { create(:listing_view, user: owner, listing: build_feed_card) }
      get "/api/v1/my/viewed_listings", headers: headers, as: :json

      small_page = count_queries { get "/api/v1/my/viewed_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      12.times { create(:listing_view, user: owner, listing: build_feed_card) }
      large_page = count_queries { get "/api/v1/my/viewed_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(15)

      expect(large_page).to eq(small_page),
        "my/viewed_listings: #{small_page} queries for 3 rows, #{large_page} for 15"
    end

    it "GET /api/v1/my/hidden_listings — flat slope" do
      3.times { create(:hidden_listing, user: owner, listing: build_feed_card) }
      get "/api/v1/my/hidden_listings", headers: headers, as: :json

      small_page = count_queries { get "/api/v1/my/hidden_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      12.times { create(:hidden_listing, user: owner, listing: build_feed_card) }
      large_page = count_queries { get "/api/v1/my/hidden_listings", headers: headers, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(15)

      expect(large_page).to eq(small_page),
        "my/hidden_listings: #{small_page} queries for 3 rows, #{large_page} for 15"
    end

    it "GET /api/v1/users/:id/sold_listings — flat slope" do
      seller = create(:user)
      3.times { build_feed_card.update!(user: seller, status: :sold) }
      path = "/api/v1/users/#{seller.id}/sold_listings"
      get path, as: :json

      small_page = count_queries { get path, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(3)

      12.times { build_feed_card.update!(user: seller, status: :sold) }
      large_page = count_queries { get path, as: :json }
      expect(JSON.parse(response.body)["listings"].size).to eq(15)

      expect(large_page).to eq(small_page),
        "users/:id/sold_listings: #{small_page} queries for 3 rows, #{large_page} for 15"
    end
  end
end
