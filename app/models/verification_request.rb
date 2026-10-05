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
#   * the FULL document number is kept, encrypted (owner decision 2026-10-05):
#     `document_number` (Active Record Encryption, non-deterministic; keys in
#     config/initializers/active_record_encryption.rb) + `document_number_digest`
#     (HMAC-SHA256, indexed) to spot the same ID on another account. Never in
#     an API response or a log; apps show ••••document_last4.
class VerificationRequest < ApplicationRecord
  # SHOP-1: a Shop applies through the same model (docs/SHOPS.md "Verified shops").
  SUBJECT_TYPES = [ User.name, Shop.name ].freeze
  FILES_KEPT_FOR = 90.days
  DOCUMENT_URL_TTL = 5.minutes
  DOCUMENT_TOKEN_PURPOSE = :admin_verification_document
  MAX_FILE_SIZE = 10.megabytes
  # Spec: 3 requests a day. Counts requests actually sent, not failed uploads.
  DAILY_LIMIT = 3
  # A document number: digits only, a sensible length. No invented official
  # formats (owner: "if unsure, accept 6–20 digits").
  # Letters and digits, at least one digit (owner, 2026-10-05: IDs can carry letters).
  DOCUMENT_NUMBER_FORMAT = /\A(?=.*\d)[0-9A-Z]{5,20}\z/
  FILES = %i[front back selfie proof].freeze

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
  # Owner, 2026-10-05: ONLY the e-Tazkira is accepted, for people and for a
  # shop's owner. Paper Tazkira, CNIC, Kart-e Melli, passport and licence stay
  # in the enum for old rows but can no longer be sent.
  USER_DOCUMENT_TYPES = %w[e_tazkira].freeze
  # ── SHOP-1 ──────────────────────────────────────────────────────────────────
  # A shop sends the shop front (`front`), the OWNER's e-Tazkira (`back`) with
  # its number, a REQUIRED proof that the business is theirs (`proof`: licence,
  # rental contract, tax paper… any document; owner 2026-10-05) and a phone the
  # team calls back. No selfie.
  SHOP_DOCUMENT_TYPES = USER_DOCUMENT_TYPES
  # What each file IS, per subject — the admin card labels them with this.
  FILE_LABELS = {
    User.name => { front: "document_front", back: "document_back", selfie: "selfie" },
    Shop.name => { front: "shop_front", back: "owner_e_tazkira", proof: "business_proof" }
  }.freeze
  # A business licence number keeps its letters ("KBL-2021/0456" → "KBL20210456");
  # a person's ID number stays digits-only, so the same Tazkira matches across
  # users and shops (same_number_elsewhere).
  LICENCE_NUMBER_FORMAT = /\A[0-9A-Z]{3,40}\z/
  # The shop checklist (docs/SHOPS.md, "What the admin checks").
  SHOP_CHECKLIST = %w[shop_real name_matches address_right owner_real phone_works listings_clean no_bad_history].freeze
  # ── end SHOP-1 ──

  has_one_attached :front
  has_one_attached :back
  has_one_attached :selfie
  has_one_attached :proof # SHOP-1: proof of business (shops only)

  encrypts :document_number
  before_validation :normalize_document_number

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :reason_code, inclusion: { in: REJECT_REASONS + REVOKE_REASONS }, allow_nil: true
  FILES.each do |name|
    validates name, attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: MAX_FILE_SIZE }
  end

  # What a fresh application must carry. Only on create: a decided request keeps
  # its row after its files are purged.
  with_options on: :create, if: -> { requested? && !shop_subject? } do
    validates :document_type, inclusion: { in: USER_DOCUMENT_TYPES }
    validates :name_on_document, presence: true, length: { maximum: 120 }
    validates :document_number, format: { with: DOCUMENT_NUMBER_FORMAT }
    validates :front, :selfie, presence: true
    validates :back, presence: true, if: :two_sided?
  end
  # SHOP-1 — what a shop's application must carry (see SHOP_DOCUMENT_TYPES).
  with_options on: :create, if: -> { requested? && shop_subject? } do
    validates :document_type, inclusion: { in: SHOP_DOCUMENT_TYPES }
    validates :front, :back, :proof, presence: true
    validates :phone, presence: true, length: { maximum: 30 }
    validates :document_number, format: { with: DOCUMENT_NUMBER_FORMAT }
  end
  validate :subject_must_be_eligible, on: :create, if: :requested?

  scope :recent, -> { order(created_at: :desc) }
  scope :for_users, -> { where(subject_type: User.name) }
  scope :for_shops, -> { where(subject_type: Shop.name) }
  scope :purgeable, -> { where(files_purged_at: nil).where(decided_at: ...FILES_KEPT_FOR.ago) }

  # HMAC of the normalized number with its own secret: equal numbers give equal
  # digests on every account, and the digest alone reveals nothing.
  def self.digest_for(number)
    hmac(normalize_number(number))
  end

  # SHOP-1: the HMAC of an already-normalized value (a licence keeps letters,
  # so it must not go through normalize_number's digits-only filter).
  def self.hmac(normalized)
    return nil if normalized.blank?

    OpenSSL::HMAC.hexdigest("SHA256", number_digest_key, normalized)
  end

  # SHOP-1: a licence number → ASCII digits + upper-case letters, nothing else.
  def self.normalize_licence(raw)
    raw.to_s.tr("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789").upcase.gsub(/[^0-9A-Z]/, "")
  end

  # Persian/Arabic-Indic digits → ASCII, letters upper-cased; spaces, dashes and
  # the like dropped. Same rule as the clients' normalizeDocumentNumber.
  def self.normalize_number(raw)
    raw.to_s.tr("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789").upcase.gsub(/[^0-9A-Z]/, "")
  end

  # credentials.verification.number_hmac_key or ENV in production; derived from
  # secret_key_base elsewhere (never committed).
  def self.number_digest_key
    key = Rails.application.credentials.dig(:verification, :number_hmac_key) || ENV["VERIFICATION_NUMBER_HMAC_KEY"]
    return key if key.present?
    raise "VERIFICATION_NUMBER_HMAC_KEY is not set" if Rails.env.production?

    Rails.application.key_generator.generate_key("verification/number_digest", 32)
  end

  # Other accounts' requests with the same ID number (any status, deleted or
  # banned accounts included). For the admin only; the applicant is never told.
  def same_number_elsewhere
    return self.class.none if document_number_digest.blank?

    self.class.where(document_number_digest: document_number_digest)
        .where.not(subject_type: subject_type, subject_id: subject_id)
        .includes(:subject).order(created_at: :desc)
  end

  def self.daily_limit_reached?(user)
    where(requested_by: user).where(created_at: 1.day.ago..).count >= DAILY_LIMIT
  end

  def two_sided? = TWO_SIDED.include?(document_type.to_s)

  def shop_subject? = subject_type == Shop.name

  def checklist_keys = shop_subject? ? SHOP_CHECKLIST : CHECKLIST

  # The admin's label for one of this request's files (SHOP-1: per subject).
  def file_label(name) = FILE_LABELS.fetch(subject_type, FILE_LABELS[User.name]).fetch(name.to_sym, name.to_s)

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
      subject.verification_granted!(admin)
    end
    SupportNoticeJob.enqueue(subject.verification_notice_recipient, subject.verification_notice_key(:verified))
  end

  def reject!(admin:, reason_code:, reason_text: nil, checklist: {})
    raise ArgumentError, "only a waiting request can be rejected" unless requested?

    decide!(:rejected, admin, reason_code, reason_text, REJECT_REASONS, checklist: checklist)
    SupportNoticeJob.enqueue(subject.verification_notice_recipient, subject.verification_notice_key(:rejected))
  end

  def revoke!(admin:, reason_code:, reason_text: nil)
    raise ArgumentError, "only an approved request can be revoked" unless approved?

    transaction do
      decide!(:revoked, admin, reason_code, reason_text, REVOKE_REASONS)
      subject.verification_withdrawn!
    end
    SupportNoticeJob.enqueue(subject.verification_notice_recipient, subject.verification_notice_key(:revoked))
  end

  # Revoke a badge that was switched on by hand (no approved request to revoke):
  # a decided row is written so the reason shows on the person's status card.
  # SHOP-1: `subject` may be a Shop; the row is then written in its owner's name.
  def self.revoke_badge!(subject, admin:, reason_code:, reason_text: nil)
    transaction do
      requester = subject.is_a?(Shop) ? subject.owner : subject
      request = subject.verification_requests.approved.recent.first ||
                subject.verification_requests.create!(requested_by: requester, status: :approved, decided_at: Time.current)
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

  def normalize_document_number
    return unless will_save_change_to_document_number? && document_number.present?

    # SHOP-1: a licence keeps its letters; every ID number is digits-only.
    normalized = licence? ? self.class.normalize_licence(document_number) : self.class.normalize_number(document_number)
    self.document_number = normalized
    self.document_last4 = normalized.last(4)
    self.document_number_digest = self.class.hmac(normalized)
  end

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
    checklist_keys.index_with { |key| ActiveModel::Type::Boolean.new.cast(hash[key] || hash[key.to_sym]) || false }
  end

  # Users and (SHOP-1) shops both answer verified? and verification_missing.
  def subject_must_be_eligible
    return unless subject.respond_to?(:verification_missing)

    errors.add(:subject, :already_verified) if subject.verified?
    missing = subject.verification_missing
    errors.add(:subject, :not_eligible, missing: missing.join(", ")) if missing.any?
  end
end
