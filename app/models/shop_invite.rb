# SHOP-3 — an invitation to join a shop as Staff (hatiwal-mobile/docs/SHOPS.md,
# "Phase 3 — the team"). A plain LINK (email nil, the main path) works for
# whoever opens it; an EMAIL invite works only for the account whose email is
# that address AND confirmed (phones are not verified on Hatiwal, so there are
# no phone invites). Nobody joins without accepting; an invite works once and
# for TTL.
class ShopInvite < ApplicationRecord
  TTL = 7.days
  DAILY_LIMIT = 20 # per shop
  TOKEN_BYTES = 24

  # 410 Gone for an invite that can no longer be used; 403 for the wrong account.
  class Refused < StandardError
    attr_reader :code, :status

    def initialize(code, status: :unprocessable_entity)
      @code = code
      @status = status
      super(I18n.t("shops.team.errors.#{code}", default: code.to_s.humanize))
    end
  end

  belongs_to :shop
  belongs_to :invited_by, class_name: User.name
  belongs_to :accepted_by, class_name: User.name, optional: true

  enum :role, ShopMember.roles.slice("staff")
  enum :status, { pending: 0, accepted: 1, declined: 2, cancelled: 3 }

  before_validation :normalize_email
  before_validation :fill_token_and_expiry, on: :create

  validates :token, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :expires_at, presence: true

  scope :live, -> { pending.where("shop_invites.expires_at > ?", Time.current) }
  scope :pending_first, -> { order(Arel.sql("CASE WHEN shop_invites.status = 0 THEN 0 ELSE 1 END"), created_at: :desc) }

  def self.public_url(token)
    base = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    base.present? ? "#{base.chomp('/')}/join/#{token}" : "hatiwal://join/#{token}"
  end

  def url = self.class.public_url(token)
  def expired? = pending? && expires_at <= Time.current
  def link? = email.blank?

  # What the invite says right now, for the public page and the owner's list.
  def display_status
    expired? ? "expired" : status
  end

  # Opening it as `user`: why it can't be used, or nil. Order matters: a used
  # or cancelled invite says so even to the wrong account.
  def refusal_for(user)
    return Refused.new(:invite_used, status: :gone) if accepted? || declined?
    return Refused.new(:invite_cancelled, status: :gone) if cancelled?
    return Refused.new(:invite_expired, status: :gone) if expired?
    return Refused.new(:shop_unavailable) unless shop.active?
    return Refused.new(:already_member) if shop.member?(user)
    # The invite's own address, not confirmed yet: say so (the person can fix it),
    # rather than "this invite is for another account".
    return Refused.new(:invite_email_unconfirmed, status: :forbidden) if email_unconfirmed_for?(user)
    return Refused.new(:invite_wrong_account, status: :forbidden) unless for_account?(user)
    return Refused.new(:team_full) if shop.team_full?

    nil
  end

  # A link invite fits anyone; an email invite only that CONFIRMED address.
  def for_account?(user)
    return true if link?

    user.confirmed_at.present? && user.email.to_s.strip.casecmp?(email)
  end

  def email_unconfirmed_for?(user)
    !link? && user.confirmed_at.blank? && user.email.to_s.strip.casecmp?(email)
  end

  def accept!(user)
    with_lock do
      refusal = refusal_for(user)
      raise refusal if refusal

      member = shop.shop_members.create!(user: user, role: :staff, invited_by: invited_by)
      update!(status: :accepted, accepted_by: user, decided_at: Time.current)
      ShopAuditEvent.record!(shop, :joined, actor: user, target_user: user, invite_id: id)
      ShopTeamPushJob.perform_later("shop_member_joined", shop.owner_id, shop.id, user.id)
      member
    end
  end

  def decline!(user)
    with_lock do
      refusal = refusal_for(user)
      raise refusal if refusal && refusal.code != :already_member

      update!(status: :declined, accepted_by: nil, decided_at: Time.current)
      ShopAuditEvent.record!(shop, :declined, actor: user, invite_id: id)
    end
  end

  def cancel!(actor)
    return unless pending?

    update!(status: :cancelled, decided_at: Time.current)
    ShopAuditEvent.record!(shop, :invite_cancelled, actor: actor, invite_id: id)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def fill_token_and_expiry
    self.token ||= SecureRandom.urlsafe_base64(TOKEN_BYTES)
    self.expires_at ||= TTL.from_now
  end
end
