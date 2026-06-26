require "rails_helper"

RSpec.describe "Api::V1::SavedSearches", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:category) { create(:category) }
  let(:headers) { auth_headers_for(user) }

  # Helper: create a listing and back-date created_at via update_column
  # to reliably control its position relative to last_viewed_at.
  # Accepts optional trait symbols followed by keyword overrides:
  #   create_listing_at(1.hour.ago, :active, user: seller, category: cat)
  def create_listing_at(time, *traits, **attrs)
    listing = create(:listing, *traits, **attrs)
    listing.update_column(:created_at, time)
    listing
  end

  describe "GET /api/v1/users/saved_searches" do
    it "requires authentication" do
      get "/api/v1/users/saved_searches"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns user's saved searches, most recent first" do
      ss1 = create(:saved_search, user: user, location: "Kabul", created_at: 2.days.ago)
      ss2 = create(:saved_search, user: user, location: "Kandahar", created_at: 1.day.ago)

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      if response.status != 200
        puts "DEBUG: Status #{response.status}, Body: #{response.body}"
      end
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["saved_searches"]).to be_an(Array)
      locations = body["saved_searches"].map { |s| s["location"] }
      expect(locations).to eq([ "Kandahar", "Kabul" ])
    end

    it "includes new_matches_count in each saved search" do
      seller = create(:user)
      cat    = create(:category)
      ss = create(:saved_search, user: user, location: nil, category: cat, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      record = body["saved_searches"].find { |s| s["id"] == ss.id }
      expect(record["new_matches_count"]).to eq(1)
    end

    it "does not count listings from a seller the user has blocked" do
      blocked_seller = create(:user)
      cat = create(:category)
      create(:block, blocker: user, blocked: blocked_seller)
      ss = create(:saved_search, user: user, location: nil, category: cat, last_viewed_at: 2.hours.ago)
      create_listing_at(1.hour.ago, :active, user: blocked_seller, category: cat)

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      body = JSON.parse(response.body)
      record = body["saved_searches"].find { |s| s["id"] == ss.id }
      expect(record["new_matches_count"]).to eq(0)
    end

    it "returns new_matches_count: 0 when no new listings match" do
      ss = create(:saved_search, user: user, last_viewed_at: 1.hour.ago)

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      body = JSON.parse(response.body)
      record = body["saved_searches"].find { |s| s["id"] == ss.id }
      expect(record["new_matches_count"]).to eq(0)
    end

    it "returns at most #{SavedSearch::MAX_PER_USER} searches" do
      6.times { create(:saved_search, user: user) }

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["saved_searches"].length).to be <= SavedSearch::MAX_PER_USER
    end

    it "does not return other users' searches" do
      other_user = create(:user)
      create(:saved_search, user: user)
      create(:saved_search, user: other_user)

      get "/api/v1/users/saved_searches", headers: headers, as: :json

      body = JSON.parse(response.body)
      expect(body["saved_searches"].length).to eq(1)
    end
  end

  describe "POST /api/v1/users/saved_searches" do
    it "requires authentication" do
      post "/api/v1/users/saved_searches", params: { location: "Kabul" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a saved search with filters" do
      expect do
        post "/api/v1/users/saved_searches",
             params: { location: "Kabul", category_id: category.id, price_min: 1000, price_max: 5000 },
             headers: headers, as: :json
      end.to change(SavedSearch, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["saved_search"]["location"]).to eq("Kabul")
      expect(body["saved_search"]["category_id"]).to eq(category.id)
      expect(body["saved_search"]["price_min"]).to eq(1000)
      expect(body["saved_search"]["price_max"]).to eq(5000)
    end

    it "associates search with current user" do
      post "/api/v1/users/saved_searches",
           params: { location: "Kandahar" },
           headers: headers, as: :json

      search = SavedSearch.last
      expect(search.user_id).to eq(user.id)
    end

    it "de-duplicates identical filter combinations" do
      2.times do
        post "/api/v1/users/saved_searches",
             params: { location: "Kabul", price_min: 100, price_max: 900 },
             headers: headers, as: :json
      end

      matching = user.saved_searches.where(location: "Kabul", price_min: 100, price_max: 900)
      expect(matching.count).to eq(1)
    end

    it "keeps only the most recent #{SavedSearch::MAX_PER_USER} searches" do
      6.times do |i|
        post "/api/v1/users/saved_searches",
             params: { location: "City#{i}" },
             headers: headers, as: :json
      end

      expect(user.saved_searches.count).to eq(SavedSearch::MAX_PER_USER)
    end

    it "creates a saved search with geolocation" do
      post "/api/v1/users/saved_searches",
           params: { location: "Kabul", latitude: 34.52, longitude: 69.18, radius: 5 },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["saved_search"]["latitude"]).to eq(34.52)
      expect(body["saved_search"]["longitude"]).to eq(69.18)
      expect(body["saved_search"]["radius"]).to eq(5)
      expect(body["saved_search"]["location_based"]).to be true
    end

    it "rejects invalid latitude" do
      post "/api/v1/users/saved_searches",
           params: { location: "Kabul", latitude: 91, longitude: 69.18, radius: 5 },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalid longitude" do
      post "/api/v1/users/saved_searches",
           params: { location: "Kabul", latitude: 34.52, longitude: 181, radius: 5 },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects invalid radius" do
      post "/api/v1/users/saved_searches",
           params: { location: "Kabul", latitude: 34.52, longitude: 69.18, radius: -5 },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/users/saved_searches/:id" do
    # Use let! so the record exists BEFORE the change-matcher captures the count.
    let!(:saved_search) { create(:saved_search, user: user) }

    it "requires authentication" do
      delete "/api/v1/users/saved_searches/#{saved_search.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "deletes the user's own saved search" do
      expect do
        delete "/api/v1/users/saved_searches/#{saved_search.id}", headers: headers, as: :json
      end.to change(SavedSearch, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "forbids deleting another user's search" do
      other_user = create(:user)
      create(:saved_search, user: other_user)
      other_headers = auth_headers_for(other_user)

      delete "/api/v1/users/saved_searches/#{saved_search.id}", headers: other_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(SavedSearch.find_by(id: saved_search.id)).to be_present
    end
  end

  describe "PUT /api/v1/users/saved_searches/:id/mark_seen" do
    let(:seller) { create(:user) }
    let(:cat)    { create(:category) }
    let!(:saved_search) { create(:saved_search, user: user, location: nil, category: cat, last_viewed_at: 2.hours.ago) }
    let!(:new_listing) do
      # A browsable listing posted after last_viewed_at so new_matches_count starts at 1
      create_listing_at(1.hour.ago, :active, user: seller, category: cat)
    end

    it "requires authentication" do
      put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "stamps last_viewed_at and returns the updated record" do
      travel_to(Time.current) do
        put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen",
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        record = body["saved_search"]
        expect(record["last_viewed_at"]).to be_present
        expect(Time.zone.parse(record["last_viewed_at"])).to be_within(1.second).of(Time.current)
      end
    end

    it "resets new_matches_count to 0 after mark_seen" do
      travel_to(Time.current) do
        put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen",
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        # After stamping last_viewed_at = now, new_listing (1 hour ago) is no longer "new"
        expect(body["saved_search"]["new_matches_count"]).to eq(0)
      end
    end

    it "persists last_viewed_at on the database record" do
      travel_to(Time.current) do
        put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen",
            headers: headers, as: :json

        saved_search.reload
        expect(saved_search.last_viewed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "is forbidden for another user (owner-only)" do
      other_user    = create(:user)
      other_headers = auth_headers_for(other_user)

      put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen",
          headers: other_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "only counts new browsable listings after the updated last_viewed_at" do
      travel_to(Time.current) do
        # Before mark_seen the listing (posted 1 hour ago) is new relative to last_viewed_at (2 hours ago)
        expect(saved_search.new_matches_count).to eq(1)

        put "/api/v1/users/saved_searches/#{saved_search.id}/mark_seen",
            headers: headers, as: :json

        saved_search.reload
        # Now last_viewed_at = now, so the listing 1 hour ago is no longer "new"
        expect(saved_search.new_matches_count).to eq(0)
      end
    end

    it "excludes non-browsable listings (draft/sold/expired/removed) from new_matches_count" do
      draft_l   = create_listing_at(30.minutes.ago, status: :draft,    user: seller, category: cat)
      sold_l    = create_listing_at(30.minutes.ago, status: :sold,     user: seller, category: cat)
      expired_l = create_listing_at(30.minutes.ago, :active,           user: seller, category: cat)
      removed_l = create_listing_at(30.minutes.ago, :active,           user: seller, category: cat)
      expired_l.update_column(:expires_at, 10.minutes.ago)
      removed_l.update_column(:removed_at, 10.minutes.ago)

      get "/api/v1/users/saved_searches", headers: headers, as: :json
      body = JSON.parse(response.body)
      record = body["saved_searches"].find { |s| s["id"] == saved_search.id }
      # Only the 1 active+browsable listing (new_listing from let!) should count
      expect(record["new_matches_count"]).to eq(1)

      [ draft_l, sold_l, expired_l, removed_l ] # suppress unused variable warnings
    end
  end
end
