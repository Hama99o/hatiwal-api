require "rails_helper"

# The API side of the "photos" holes: publishing without a photo must come back
# as an ordinary 422 the seller can read, and a photo REJECTED by the attachment
# validation must not be silently dropped from an otherwise-successful edit.
RSpec.describe "My listings — photo rules", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  def disguised_zip
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/not_an_image.zip"), "image/jpeg", original_filename: "photo.jpg"
    )
  end

  def real_photo
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg")
  end

  describe "PUT /api/v1/my/listings/:id/publish" do
    it "refuses a listing with no photo, with a message the seller can act on" do
      listing = create(:listing, user: seller)

      put "/api/v1/my/listings/#{listing.id}/publish", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].join).to match(/at least one photo/)
      expect(listing.reload).to be_draft
    end

    # Regression guard: publishing used to be `active!` + `renew!`, two bang
    # writes. A refusable publish would have raised RecordInvalid through those
    # and reached the seller as a 500 with no field errors.
    it "never answers a refused publish with a 5xx" do
      listing = create(:listing, user: seller)

      put "/api/v1/my/listings/#{listing.id}/publish", headers: headers, as: :json

      expect(response.status).to be < 500
    end

    it "publishes a listing that has a photo" do
      listing = create(:listing, :with_image, user: seller)

      put "/api/v1/my/listings/#{listing.id}/publish", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload).to be_active
    end
  end

  describe "POST /api/v1/my/listings" do
    it "rejects a non-image uploaded as a photo" do
      post "/api/v1/my/listings",
           params:  { listing: attributes_for(:listing).merge(category_id: create(:category).id, images: [ disguised_zip ]) },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"].join).to match(/unsupported file type/)
      expect(Listing.count).to eq(0)
    end

    it "accepts a real photo" do
      post "/api/v1/my/listings",
           params:  { listing: attributes_for(:listing).merge(category_id: create(:category).id, images: [ real_photo ]) },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(Listing.last.images.count).to eq(1)
    end
  end

  describe "PUT /api/v1/my/listings/:id" do
    # Active Storage's `attach` saves the record itself, so a rejected file used
    # to vanish with a 200: the edit "succeeded" and the photo was simply not
    # there. The failure has to surface.
    it "returns 422 rather than silently dropping a rejected photo" do
      listing = create(:listing, :with_image, user: seller)

      put "/api/v1/my/listings/#{listing.id}",
          params:  { listing: { title: "Reduced price", images: [ disguised_zip ] } },
          headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(listing.reload.images.count).to eq(1)
    end

    it "still appends a valid photo without wiping the gallery" do
      listing = create(:listing, :with_image, user: seller)

      put "/api/v1/my/listings/#{listing.id}",
          params:  { listing: { title: "Reduced price", images: [ real_photo ] } },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(listing.reload.images.count).to eq(2)
      expect(listing.title).to eq("Reduced price")
    end
  end
end
