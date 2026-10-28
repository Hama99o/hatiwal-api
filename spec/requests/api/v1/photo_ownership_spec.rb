require "rails_helper"

# Security review (2026-10-28): a photo id is a blob's signed id, and every
# listing's ids are public (`image_attachments`, `gallery_photos[].id`). Removing
# or keeping a photo by id must only ever touch the caller's OWN listing or shop:
# another listing's or shop's id is ignored, never purged, never taken over.
# (removed_image_ids dates from 1.1.x; keep_ids from SHOP-MEDIA.)
RSpec.describe "Photo ids only reach their own listing or shop", type: :request do
  def h(user) = auth_headers_for(user)
  def file_exists?(blob) = ActiveStorage::Blob.service.exist?(blob.key)

  let(:alice) { create(:user) }
  let(:bob)   { create(:user) }

  describe "listing removed_image_ids" do
    let(:alices) { create(:listing, :active, :with_image, user: alice) }
    let(:bobs)   { create(:listing, :active, :with_image, user: bob) }

    it "another seller's photo id in my edit: their photo, its blob and its file stay" do
      bob_blob = bobs.images.first.blob
      put "/api/v1/my/listings/#{alices.id}", params: { listing: { title: "Mine", removed_image_ids: [ bob_blob.signed_id ] } },
                                               headers: h(alice), as: :json

      expect(response).to have_http_status(:ok)
      expect(bobs.reload.images.map(&:blob_id)).to eq([ bob_blob.id ])
      expect(ActiveStorage::Blob.exists?(bob_blob.id)).to be(true)
      expect(file_exists?(bob_blob)).to be(true)
      expect(alices.reload.images.count).to eq(1) # mine is untouched too
    end

    it "removing my own photo still works" do
      mine = alices.images.first.blob
      put "/api/v1/my/listings/#{alices.id}", params: { listing: { title: "Mine", removed_image_ids: [ mine.signed_id ] } },
                                               headers: h(alice), as: :json

      expect(response).to have_http_status(:ok)
      expect(alices.reload.images).to be_empty
    end

    it "a duplicate has its own copies: removing the copy's photo leaves the original's" do
      post "/api/v1/my/listings/#{alices.id}/duplicate", headers: h(alice), as: :json
      expect(response).to have_http_status(:created)
      copy = Listing.find(JSON.parse(response.body).then { |j| j.dig("listing", "id") || j["id"] })
      original_blob = alices.images.first.blob
      expect(copy.images.first.blob_id).not_to eq(original_blob.id)

      put "/api/v1/my/listings/#{copy.id}", params: { listing: { title: "Copy", removed_image_ids: [ copy.images.first.blob.signed_id ] } },
                                             headers: h(alice), as: :json
      expect(response).to have_http_status(:ok)
      expect(file_exists?(original_blob)).to be(true)
      expect(alices.reload.images.count).to eq(1)
    end
  end

  describe "shop gallery keep_ids" do
    let(:alices_shop) { create(:shop, :with_gallery, owner: alice) }
    let(:bobs_shop)   { create(:shop, :with_gallery, owner: bob) }

    it "another shop's photo id in my gallery: not taken over, and their gallery is untouched" do
      bobs_blobs = bobs_shop.gallery_photos.blobs.to_a
      put "/api/v1/shops/#{alices_shop.id}/gallery", params: { gallery: { keep_ids: bobs_blobs.map(&:signed_id) } },
                                                     headers: h(alice)

      expect(response).to have_http_status(:ok)
      expect(alices_shop.reload.gallery_photos.blobs.map(&:id) & bobs_blobs.map(&:id)).to be_empty
      expect(bobs_shop.reload.gallery_photos.blobs.map(&:id)).to match_array(bobs_blobs.map(&:id))
      expect(bobs_blobs).to all(satisfy { |b| file_exists?(b) })
    end

    it "nobody but the shop's team may change its gallery: 403, nothing changes" do
      before = bobs_shop.gallery_photos.blobs.map(&:id)
      put "/api/v1/shops/#{bobs_shop.id}/gallery", params: { gallery: { keep_ids: [] } }, headers: h(alice)

      expect(response).to have_http_status(:forbidden)
      expect(bobs_shop.reload.gallery_photos.blobs.map(&:id)).to match_array(before)
    end
  end
end
