# VID (1.1.9, docs/LISTING_VIDEO.md) — a listing's one optional video.
#
#   PUT    /api/v1/my/listings/:listing_id/video  multipart: video (mp4/mov,
#          ≤ 25 MB), poster (image, optional), duration_s (optional)
#   DELETE /api/v1/my/listings/:listing_id/video
#
# Kept apart from the listing save so the listing publishes with its photos and
# the video follows in the background. Multipart through this authenticated
# controller, not Active Storage direct upload: direct uploads are closed on
# purpose (config/initializers/no_active_storage_writes.rb).
class Api::V1::My::ListingVideosController < Api::V1::BaseController
  before_action :set_listing

  # A retry re-sends the whole file, so leave room for a bad connection; a
  # script refilling the disk is what this stops.
  throttle to: 30, within: 1.day, by: :user, only: :update

  def update
    authorize @listing, :update_video?
    unless params[:video].is_a?(ActionDispatch::Http::UploadedFile)
      return render_coded_error("Upload a video", code: :invalid_upload, status: :unprocessable_entity)
    end

    if @listing.attach_video!(file: params[:video], poster: params[:poster], duration_s: params[:duration_s])
      render_blue(ListingSerializer, @listing, view: :owner_detailed)
    else
      render_unprocessable_entity(@listing)
    end
  end

  def destroy
    authorize @listing, :destroy_video?
    @listing.purge_video!
    render_blue(ListingSerializer, @listing.reload, view: :owner_detailed)
  end

  private

  # SHOP-3: a shop's products are every member's to manage (as My::Listings).
  def set_listing
    @listing = current_user.manageable_listings.find(params[:listing_id])
    @listing.acting_user = current_user
  end
end
