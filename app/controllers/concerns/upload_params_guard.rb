# frozen_string_literal: true

# Hunt-2 (1.1.7): an upload param takes ONLY a file uploaded in this request.
#
# Active Storage also accepts a blob's signed_id string wherever it accepts a
# file, and listing detail echoes the signed ids of a listing's photos (the
# edit form removes one by it). Anyone could attach SOMEONE ELSE's photo blob
# to their own listing, avatar, shop, chat message or verification request,
# and purging their copy then deleted the owner's file. No client sends a
# signed id in these params (every upload is multipart), so anything that is
# not an uploaded file is refused with 422 invalid_upload before the action
# runs.
module UploadParamsGuard
  extend ActiveSupport::Concern

  # Every attachment param on the JSON API, as a path into params.
  UPLOAD_PARAM_PATHS = [
    %i[listing images],
    %i[video], %i[poster], # VID / SHOP-MEDIA: VideoUploadActions
    %i[gallery photos], # SHOP-MEDIA: ShopGalleriesController
    %i[user avatar],
    %i[shop logo], %i[shop cover],
    %i[attachment],
    %i[verification_request front], %i[verification_request back],
    %i[verification_request selfie], %i[verification_request proof]
  ].freeze

  included do
    before_action :reject_non_file_uploads!, if: -> { controller_path.start_with?("api/") }
  end

  private

  def reject_non_file_uploads!
    return unless UPLOAD_PARAM_PATHS.any? { |path| non_file_upload?(upload_param_at(path)) }

    render_coded_error("Upload a file", code: :invalid_upload, status: :unprocessable_entity)
  end

  def upload_param_at(path)
    path.reduce(params) { |node, key| node.respond_to?(:key?) && node.key?(key) ? node[key] : (return nil) }
  end

  # Blank values are left to the action, as before (nothing gets attached).
  def non_file_upload?(value)
    Array.wrap(value).any? { |v| v.present? && !v.is_a?(ActionDispatch::Http::UploadedFile) }
  end
end
