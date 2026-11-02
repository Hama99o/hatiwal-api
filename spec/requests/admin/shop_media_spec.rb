require "rails_helper"

# SHOP-MEDIA: moderators see a shop's photos + video and remove any of them.
RSpec.describe "Admin shop media", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:shop)  { create(:shop, :with_video, :with_gallery) }

  before { sign_in admin, scope: :admin_user }

  it "shows the player and the photos on the shop page" do
    get admin_shop_path(shop)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<video controls preload="none"', shop.video.blob.signed_id, "Photos &amp; video")
    expect(response.body.scan("Remove this photo?").size).to eq(2)
  end

  it "removes the video, logged" do
    expect { patch remove_video_admin_shop_path(shop) }.to change(AdminAuditLog, :count).by(1)
    expect(shop.reload.video).not_to be_attached
    expect(AdminAuditLog.last).to have_attributes(action: "remove_shop_video", target: shop)
  end

  it "removes one photo, logged; the other stays" do
    photo_id = shop.gallery_photo_entries.first[:id]
    perform_enqueued_jobs { patch remove_gallery_photo_admin_shop_path(shop, photo_id: photo_id) }
    expect(shop.reload.gallery_photos.count).to eq(1)
    expect(AdminAuditLog.last).to have_attributes(action: "remove_shop_photo", target: shop)
  end

  it "refuses a photo of another shop" do
    other = create(:shop, :with_gallery)
    patch remove_gallery_photo_admin_shop_path(shop, photo_id: other.gallery_photo_entries.first[:id])
    expect(flash[:alert]).to match(/not this shop's/)
    expect(other.reload.gallery_photos.count).to eq(2)
  end

  it "a flag on the shop shows its video" do
    flag = create(:flag, :on_shop, flaggable: shop)
    get admin_flag_path(flag)
    expect(response.body).to include('<video controls preload="none"')
  end
end
