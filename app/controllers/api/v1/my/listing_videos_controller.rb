# VID (1.1.9, docs/LISTING_VIDEO.md) — a listing's one video:
#   PUT/DELETE /api/v1/my/listings/:listing_id/video (VideoUploadActions).
# Kept apart from the listing save so the listing publishes with its photos and
# the video follows in the background.
class Api::V1::My::ListingVideosController < Api::V1::BaseController
  include VideoUploadActions

  before_action :set_listing

  private

  # SHOP-3: a shop's products are every member's to manage (as My::Listings).
  def set_listing
    @listing = current_user.manageable_listings.find(params[:listing_id])
    @listing.acting_user = current_user
  end

  def video_record = @listing

  def authorize_video!(action)
    authorize @listing, action == :update ? :update_video? : :destroy_video?
  end

  def render_video_record
    render_blue(ListingSerializer, @listing, view: :owner_detailed)
  end
end
