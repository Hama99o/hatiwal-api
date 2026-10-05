# VER-1: ID photos (VerificationRequest front/back/selfie) are PRIVATE.
#
# Active Storage's public routes (blob redirect/proxy, representations) serve
# any blob whose signed id someone holds. The app never generates one for these
# files, but this closes the door anyway: those controllers answer 404 for any
# blob attached to a VerificationRequest. Admins read them only through
# Admin::VerificationRequestsController#document (admin session + a token that
# expires in VerificationRequest::DOCUMENT_URL_TTL, every view audit-logged).
module PrivateVerificationFiles
  extend ActiveSupport::Concern

  included do
    before_action :refuse_private_verification_blob
  end

  private

  def refuse_private_verification_blob
    blob = @blob || (@representation.respond_to?(:blob) && @representation.blob)
    return unless blob

    head :not_found if ActiveStorage::Attachment.exists?(blob_id: blob.id, record_type: VerificationRequest.name)
  end
end

Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController
  ].each { |controller| controller.include(PrivateVerificationFiles) unless controller < PrivateVerificationFiles }
end
