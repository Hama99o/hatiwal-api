# A PERMANENT URL for a PUBLIC image (listing photos, avatars, shop logos and
# covers): the blob redirect route, keyed by the blob's signed_id, never
# changes — so the apps' URL-keyed image caches hit (owner, 2026-10-09: My
# listings re-downloaded every photo on each visit).
#
# Never use it for a PRIVATE file: anyone holding a permanent link can open the
# file forever. Message attachments keep `attachment.url` (signed, expiring);
# verification files are refused by the public routes altogether
# (config/initializers/private_verification_files.rb).
# spec/edge/stable_image_urls_spec.rb guards both.
module PublicImageUrl
  module_function

  # nil when nothing is attached (or the URL cannot be built).
  def for(attachment)
    return nil unless attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?

    Rails.application.routes.url_helpers.rails_blob_url(attachment, **(ActiveStorage::Current.url_options || {}))
  rescue StandardError
    nil
  end
end
