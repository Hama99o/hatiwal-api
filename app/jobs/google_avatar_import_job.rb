# A NEW account made by Google sign-in takes its Google profile photo as its avatar
# (owner, 2026-10-29). Enqueued by Auth::GoogleAuthController on CREATE only — a
# returning or linked account is never touched. In the background so sign-in never
# waits for it or fails because of it. The fetch rules (SSRF) are Google::ProfilePhoto.
#
# At most 2 attempts in all, and only for network errors; a refusal is final. Any
# failure is logged and leaves no avatar. An avatar the person set first wins.
class GoogleAvatarImportJob < ApplicationJob
  queue_as :default

  retry_on Faraday::Error, attempts: 2, wait: 30.seconds do |job, error|
    Rails.logger.warn("Google avatar for user #{job.arguments.first}: gave up after 2 attempts (#{error.class})")
  end

  def self.enqueue_for(user, picture_url)
    perform_later(user.id, picture_url) if user&.persisted? && picture_url.present?
  end

  def perform(user_id, picture_url)
    user = User.find_by(id: user_id)
    return if user.nil? || user.deleted_at.present? || user.avatar.attached?

    photo = Google::ProfilePhoto.fetch(picture_url)
    return if user.reload.avatar.attached? # set while the photo was on its way

    ext = photo.content_type.split("/").last
    return if user.avatar.attach(io: photo.io, filename: "google-photo.#{ext}", content_type: photo.content_type)

    Rails.logger.warn("Google avatar for user #{user_id}: not saved (#{user.errors.full_messages.to_sentence})")
  rescue Google::ProfilePhoto::Refused => e
    Rails.logger.warn("Google avatar for user #{user_id}: refused (#{e.message})")
  end
end
