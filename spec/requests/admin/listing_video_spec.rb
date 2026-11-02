require "rails_helper"

# VID: moderators see a listing's video (Listing + Flag pages) and can remove it.
RSpec.describe "Admin listing video", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)   { create(:admin_user) }
  let(:listing) { create(:listing, :active, :with_image, :with_video, title: "Bike") }

  it "needs an admin session to remove a video" do
    patch remove_video_admin_listing_path(listing)
    expect(response).to redirect_to(new_admin_user_session_path)
    expect(listing.reload.video).to be_attached
  end

  describe "as an admin" do
    before { sign_in admin, scope: :admin_user }

    it "shows the player on the listing page, loading nothing until played" do
      get admin_listing_path(listing)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<video controls preload="none"', listing.video.blob.signed_id, "Remove video")
    end

    it "shows no video panel without a video" do
      get admin_listing_path(create(:listing, :active))
      expect(response.body).not_to include("<video")
    end

    it "shows the player on a flag of the listing" do
      flag = create(:flag, flaggable: listing, category: :firearms, matched_term: "bike")
      get admin_flag_path(flag)
      expect(response.body).to include('<video controls preload="none"', listing.video.blob.signed_id)
      expect(response.body).not_to include("Remove video")
    end

    it "removes the video, keeps the photos and logs it" do
      expect { patch remove_video_admin_listing_path(listing) }.to change(AdminAuditLog, :count).by(1)
      expect(response).to redirect_to(admin_listing_path(listing))
      expect(listing.reload.video).not_to be_attached
      expect(listing.images).to be_attached
      expect(AdminAuditLog.last).to have_attributes(action: "remove_listing_video", target: listing)
    end

    it "a take-down keeps the video, like the photos" do
      patch take_down_admin_listing_path(listing), params: { removed_reason: "spam" }
      expect(listing.reload).to be_removed
      expect(listing.video).to be_attached
    end
  end
end
