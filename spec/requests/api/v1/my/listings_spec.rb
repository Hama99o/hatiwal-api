require "rails_helper"

RSpec.describe "Api::V1::My::Listings", type: :request do
  let(:user)     { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }

  describe "GET /api/v1/my/listings" do
    it "requires authentication" do
      get "/api/v1/my/listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only the current user's listings" do
      mine = create(:listing, user: user)
      create(:listing) # someone else's

      get "/api/v1/my/listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ mine.id ])
    end

    it "filters by status" do
      active = create(:listing, :active, user: user)
      create(:listing, :draft, user: user)

      get "/api/v1/my/listings?status=active", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ active.id ])
    end
  end

  describe "GET /api/v1/my/listings/:id" do
    it "returns the owner's listing in detail" do
      listing = create(:listing, user: user)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["id"]).to eq(listing.id)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/my/listings" do
    let(:valid_params) do
      {
        listing: {
          title:       "iPhone 13 Pro",
          description: "Used, excellent condition",
          price:       45000,
          currency:    "AFN",
          category_id: category.id,
          location:    "Kabul, Afghanistan"
        }
      }
    end

    it "creates a draft listing owned by the current user" do
      expect do
        post "/api/v1/my/listings", params: valid_params, headers: headers, as: :json
      end.to change(user.listings, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["listing"]
      expect(body["title"]).to eq("iPhone 13 Pro")
      expect(body["status"]).to eq("draft")
    end

    it "422s on invalid params" do
      params = valid_params.deep_merge(listing: { price: -5 })
      expect do
        post "/api/v1/my/listings", params: params, headers: headers, as: :json
      end.not_to change(Listing, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end

  describe "POST /api/v1/my/listings with images (multipart)" do
    it "accepts image uploads via FormData and attaches them" do
      image = fixture_file_upload(
        Rails.root.join("spec/fixtures/files/test_image.jpg"),
        "image/jpeg"
      )

      expect do
        post "/api/v1/my/listings",
             params: {
               "listing[title]"       => "Phone with photo",
               "listing[price]"       => "20000",
               "listing[currency]"    => "AFN",
               "listing[category_id]" => category.id.to_s,
               "listing[images][]"    => image
             },
             headers: headers
      end.to change(user.listings, :count).by(1)

      expect(response).to have_http_status(:created)
    end
  end

  describe "PUT /api/v1/my/listings/:id" do
    it "updates the owner's listing" do
      listing = create(:listing, user: user, title: "Old title")
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "New title" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.title).to eq("New title")
    end

    it "422s on invalid update" do
      listing = create(:listing, user: user)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "" } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "x" } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/my/listings/:id" do
    it "destroys the owner's listing" do
      listing = create(:listing, user: user)
      expect do
        delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      end.to change(Listing, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "lifecycle transitions" do
    describe "PUT publish" do
      it "publishes a draft" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(draft.reload).to be_active
      end

      it "forbids publishing a non-draft" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT reserve" do
      it "reserves an active listing" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/reserve", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(active.reload).to be_reserved
      end

      it "forbids reserving a draft" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/reserve", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT sold" do
      it "marks a reserved listing as sold" do
        reserved = create(:listing, :reserved, user: user)
        put "/api/v1/my/listings/#{reserved.id}/sold", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(reserved.reload).to be_sold
      end

      it "forbids marking an active listing sold" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/sold", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
