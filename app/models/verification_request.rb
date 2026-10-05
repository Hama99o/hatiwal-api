# VER-1: someone asks for the Verified badge; an admin decides BY HAND.
# Spec: hatiwal-mobile/docs/VERIFICATION.md. Nothing here ever approves on its own.
#
# Polymorphic `subject` so a Shop can apply through the same model (SHOP-1).
# Today only a User is accepted (SUBJECT_TYPES).
#
# Privacy (the ID photos are the most sensitive thing Hatiwal stores):
#   * front / back / selfie are private: no serializer exposes them, and the
#     public Active Storage routes refuse their blobs
#     (config/initializers/private_verification_files.rb). Admins see them only
#     through Admin::VerificationRequestsController#document, with a token that
#     expires in DOCUMENT_URL_TTL.
#   * purged FILES_KEPT_FOR after the decision (PurgeVerificationFilesJob);
#     the decision, reason and checklist stay.
#   * only the last 4 digits of the document number are stored.
class VerificationRequest < ApplicationRecord
  SUBJECT_TYPES = [ User.name ].freeze
  FILES_KEPT_FOR = 90.days
  DOCUMENT_URL_TTL = 5.minutes
  DOCUMENT_TOKEN_PURPOSE = :admin_verification_document
  MAX_FILE_SIZE = 10.megabytes
  # Spec: 3 requests a day. Counts requests actually sent, not failed uploads.
  DAILY_LIMIT = 3
  FILES = %i[front back selfie].freeze

  # Preset rejection reasons, each translated for the person under
  # `verification.reasons.<code>` (all four locales; spec'd). `other` sends the
  # admin's free text as typed.
  REJECT_REASONS = %w[photo_not_clear name_mismatch selfie_mismatch document_not_accepted shop_sign_not_visible other].freeze
  # Revoke takes the same codes minus the photo-quality ones, plus its own.
  REVOKE_REASONS = %w[name_mismatch document_not_accepted policy_violation other].freeze
  # What the admin ticks on the card; saved with the decision.
  CHECKLIST = %w[photo_clear name_matches selfie_matches no_bad_history].freeze

  belongs_to :subject, polymorphic: true
  belongs_to :requested_by, class_name: User.name
  belongs_to :decided_by, class_name: AdminUser.name, optional: true

  enum :status, { requested: 0, approved: 1, rejected: 2, revoked: 3, cancelled: 4 }
  # validate: an unknown type from a client is a 422, not an ArgumentError 500.
  enum :document_type, { tazkira: 0, e_tazkira: 1, cnic: 2, kart_melli: 3, passport: 4, licence: 5 }, validate: { allow_nil: true }

  # Document types with a back side to photograph.
  TWO_SIDED = %w[e_tazkira cnic kart_melli].freeze
  # What a person may apply with (licence is for shops).
  USER_DOCUMENT_TYPES = %w[tazkira e_tazkira cnic kart_melli passport].freeze

  has_one_attached :front
  has_one_attached :back
  has_one_attached :selfie

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :reason_code, inclusion: { in: REJECT_REASONS + REVOKE_REASONS }, allow_nil: true
  FILES.each do |name|
    validates name, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: MAX_FILE_SIZE }
  end

  # What a fresh application must carry. Only on create: a decided request keeps
  # its row after its files are purged.
  with_options on: :create, if: :requested? do
    validates :document_type, inclusion: { in: USER_DOCUMENT_TYPES }
    validates :name_on_document, presence: true, length: { maximum: 120 }
    validates :document_last4, format: { with: /\A\d{4}\z/ }
    validates :front, :selfie, presence: true
    validates :back, presence: true, if: :two_sided?
    validate :subject_must_be_eligible
  end

  scope :recent, -> { order(created_at: :desc) }
  scope :for_users, -> { where(subject_type: User.name) }
  scope :purgeable, -> { where(files_purged_at: nil).where(decided_at: ...FILES_KEPT_FOR.ago) }

  def self.daily_limit_reached?(user)
    where(requested_by: user).where(created_at: 1.day.ago..).count >= DAILY_LIMIT
  end

  def two_sided? = TWO_SIDED.include?(document_type.to_s)

  def files_count = FILES.count { |name| public_send(name).attached? }

  def attached_files = FILES.select { |name| public_send(name).attached? }

  # ── Admin decisions ────────────────────────────────────────────────────────
  # Each one records the decision, sets/clears the badge and queues the Support
  # message in the person's language. Audit logging is the controller's job
  # (it knows the admin session); see Admin::VerificationRequestsController.

  def approve!(admin:, checklist: {})
    raise ArgumentError, "only a waiting request can be approved" unless requested?

    transaction do
      update!(status: :approved, decided_by: admin, decided_at: Time.current,
              checklist: clean_checklist(checklist), reason_code: nil, reason_text: nil)
      subject.update!(verified: true)
    end
    SupportNoticeJob.enqueue(subject, :user_verified)
  end

  def reject!(admin:, reason_code:, reason_text: nil, checklist: {})
    raise ArgumentError, "only a waiting request can be rejected" unless requested?

    decide!(:rejected, admin, reason_code, reason_text, REJECT_REASONS, checklist: checklist)
    SupportNoticeJob.enqueue(subject, :user_verification_rejected)
  end

  def revoke!(admin:, reason_code:, reason_text: nil)
    raise ArgumentError, "only an approved request can be revoked" unless approved?

    transaction do
      decide!(:revoked, admin, reason_code, reason_text, REVOKE_REASONS)
      subject.update!(verified: false)
    end
    SupportNoticeJob.enqueue(subject, :user_badge_revoked)
  end

  # Revoke a badge that was switched on by hand (no approved request to revoke):
  # a decided row is written so the reason shows on the person's status card.
  def self.revoke_badge!(user, admin:, reason_code:, reason_text: nil)
    transaction do
      request = user.verification_requests.approved.recent.first ||
                user.verification_requests.create!(requested_by: user, status: :approved, decided_at: Time.current)
      request.revoke!(admin: admin, reason_code: reason_code, reason_text: reason_text)
      request
    end
  end

  # The owner cancels while it is still waiting. Files go at once: nobody will
  # ever look at them.
  def cancel!
    raise ArgumentError, "only a waiting request can be cancelled" unless requested?

    update!(status: :cancelled, decided_at: Time.current)
    purge_files!
  end

  def purge_files!
    attached_files.each { |name| public_send(name).purge }
    update_columns(files_purged_at: Time.current, updated_at: Time.current)
  end

  # The reason in the PERSON's language, for the Support message and the card.
  def reason_for(locale)
    return reason_text if reason_code == "other" || reason_code.blank?

    I18n.t("verification.reasons.#{reason_code}", locale: locale)
  end

  # Admin view: a token for one file that stops working after DOCUMENT_URL_TTL.
  def document_token(name)
    blob = public_send(name).blob
    blob.signed_id(purpose: DOCUMENT_TOKEN_PURPOSE, expires_in: DOCUMENT_URL_TTL)
  end

  def blob_for_token(token)
    blob = ActiveStorage::Blob.find_signed(token, purpose: DOCUMENT_TOKEN_PURPOSE)
    return nil unless blob

    attached_files.map { |name| public_send(name).blob }.find { |b| b.id == blob.id }
  end

  private

  def decide!(status, admin, reason_code, reason_text, allowed, checklist: nil)
    code = reason_code.to_s
    raise ArgumentError, "unknown reason: #{code}" unless allowed.include?(code)
    raise ArgumentError, "write the reason for \"other\"" if code == "other" && reason_text.blank?

    attrs = { status: status, decided_by: admin, decided_at: Time.current,
              reason_code: code, reason_text: (reason_text.to_s.strip.presence if code == "other") }
    attrs[:checklist] = clean_checklist(checklist) unless checklist.nil?
    update!(attrs)
  end

  def clean_checklist(raw)
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    CHECKLIST.index_with { |key| ActiveModel::Type::Boolean.new.cast(hash[key] || hash[key.to_sym]) || false }
  end

  def subject_must_be_eligible
    return unless subject.is_a?(User)

    errors.add(:subject, :already_verified) if subject.verified?
    missing = subject.verification_missing
    errors.add(:subject, :not_eligible, missing: missing.join(", ")) if missing.any?
  end
end
