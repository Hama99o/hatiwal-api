require "rails_helper"

RSpec.describe "Api::V1::My::SavedListings", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/my/saved_listings" do
    it "requires authentication" do
      get "/api/v1/my/saved_listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user's saved listings with a total count" do
      saved_a = create(:listing, :active)
      saved_b = create(:listing, :active)
      create(:saved_listing, user: user, listing: saved_a)
      create(:saved_listing, user: user, listing: saved_b)
      create(:saved_listing) # another user's save

      get "/api/v1/my/saved_listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids = body["listings"].map { |l| l["id"] }
      expect(ids).to contain_exactly(saved_a.id, saved_b.id)
      expect(body["meta"]["total_count"]).to eq(2)
    end

    it "returns an empty list when nothing is saved" do
      get "/api/v1/my/saved_listings", headers: headers, as: :json
      body = JSON.parse(response.body)
      expect(body["listings"]).to eq([])
      expect(body["meta"]["total_count"]).to eq(0)
    end
  end
end
