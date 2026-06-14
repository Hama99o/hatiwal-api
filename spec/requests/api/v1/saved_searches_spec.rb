require "rails_helper"

RSpec.describe "Api::V1::SavedSearches", type: :request do
  let(:user) { create(:user) }
  let(:category) { create(:category) }
  let(:headers) { auth_headers_for(user) }

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
      other_search = create(:saved_search, user: other_user)
      other_headers = auth_headers_for(other_user)

      delete "/api/v1/users/saved_searches/#{saved_search.id}", headers: other_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(SavedSearch.find_by(id: saved_search.id)).to be_present
    end
  end
end
