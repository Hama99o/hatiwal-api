require "rails_helper"

# docs/PERFORMANCE_100K.md — the read paths measured at 100k users / 300k
# listings / 1M messages. Each example pins one fix so it cannot quietly come
# back: same payloads as before, less work to build them.
RSpec.describe "Read paths at 100k users", type: :request do
  def json = JSON.parse(response.body)

  def sql_during
    statements = []
    subscriber = ->(*, payload) { statements << payload[:sql].to_s }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end

  describe "GET /api/v1/listings — seen / saved flags" do
    let(:viewer) { create(:user) }
    # Newest first: page 1 = [l4, l3], page 2 = [l2, l1].
    let!(:listings) { (1..4).map { |i| create(:listing, :active, created_at: (10 - i).hours.ago) } }

    before do
      create(:saved_listing, user: viewer, listing: listings[1])
      ListingView.create!(user: viewer, listing: listings[0], last_viewed_at: Time.current)
    end

    it "flags the rows of a later page, looking up only that page's ids" do
      headers = auth_headers_for(viewer)
      statements = sql_during { get "/api/v1/listings", params: { page: { number: 2, size: 2 } }, headers: headers }

      rows = json["listings"].to_h { |l| [ l["id"], l.slice("is_saved", "is_viewed") ] }
      expect(rows).to eq(listings[1].id => { "is_saved" => true, "is_viewed" => false },
                         listings[0].id => { "is_saved" => false, "is_viewed" => true })
      lookups = statements.grep(/FROM "(listing_views|saved_listings)"/)
      expect(lookups.size).to eq(2)
      # Never the whole feed again as a subquery.
      expect(lookups).to all(satisfy { |sql| !sql.include?('SELECT "listings"."id" FROM "listings"') })
    end
  end

  describe "GET /api/v1/conversations — unread counts" do
    let(:seller) { create(:user) }

    it "counts unread per row on a later page and loads only that page" do
      chats = (1..3).map do |i|
        buyer = create(:user)
        chat = create(:conversation, listing: create(:listing, :active, user: seller), buyer: buyer)
        create_list(:message, i, conversation: chat, user: buyer)
        chat.update_column(:last_message_at, i.hours.ago)
        chat
      end
      headers = auth_headers_for(seller)

      loaded = 0
      counter = ->(*, payload) { loaded += payload[:record_count] if payload[:class_name] == Conversation.name }
      ActiveSupport::Notifications.subscribed(counter, "instantiation.active_record") do
        get "/api/v1/conversations", params: { page: { number: 2, size: 2 } }, headers: headers
      end

      # Ordered by last message: chats[0], chats[1] | chats[2].
      expect(json["conversations"].map { |c| [ c["id"], c["unread_count"] ] }).to eq([ [ chats[2].id, 3 ] ])
      expect(json["meta"]["pagination"]["total_count"]).to eq(3)
      # The page, not the whole inbox (it used to load every chat first).
      expect(loaded).to eq(1)
    end
  end

  describe "Conversation.seller_side_sql_for (a shop team member)" do
    it "finds the shop's chats with index-friendly SQL (no per-row EXISTS)" do
      owner = create(:user)
      shop = create(:shop, owner: owner)
      owner.reload
      chat = Conversations::StartService.new(buyer: create(:user), listing: create(:listing, :active, user: owner, shop: shop),
                                             message_body: "Salaam").call
      other = create(:conversation, listing: create(:listing, :active))

      expect(Conversation.seller_side_sql_for(owner)).not_to include("EXISTS")
      expect(Conversation.for_user(owner)).to include(chat)
      expect(Conversation.for_user(owner)).not_to include(other)
    end
  end

  describe "Listing.by_category" do
    it "still includes the subcategories, as an inlined id list" do
      parent = create(:category)
      child = create(:category, parent: parent)
      in_child = create(:listing, :active, category: child)
      create(:listing, :active)

      scope = Listing.by_category(parent.id)
      expect(scope.to_a).to eq([ in_child ])
      expect(scope.to_sql).not_to include('SELECT "categories"')
    end
  end

  describe "Listing.nearest_window_km" do
    it "stops counting once the page is covered" do
      create_list(:listing, 3, :active, latitude: 34.36, longitude: 62.21)
      statements = sql_during { Listing.nearest_window_km(Listing.browsable, 34.3529, 62.204, 2) }

      expect(statements.grep(/COUNT/)).to all(match(/LIMIT/))
    end
  end

  describe "indexes (migration 20261012100100)" do
    it "has the feed, search and non-active-seller indexes" do
      connection = ActiveRecord::Base.connection
      expect(connection.extension_enabled?("pg_trgm")).to be(true)
      %w[index_listings_browsable_feed index_listings_on_lower_title_trgm index_listings_on_lower_description_trgm].each do |name|
        expect(connection.index_name_exists?(:listings, name)).to be(true), name
      end
      expect(connection.index_name_exists?(:users, "index_users_on_id_not_active")).to be(true)
    end
  end
end
