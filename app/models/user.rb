class User < ApplicationRecord
  # :confirmable records whether the email address on an account is real.
  #
  # It is NON-BLOCKING on purpose — devise.rb sets allow_unconfirmed_access_for
  # to nil, so an unconfirmed user signs up, signs in and uses the app exactly as
  # before. What it buys today is the SIGNAL: `confirmed_at` on the user, visible
  # in Administrate, which is the prerequisite for ever making a suspension stick
  # (today a banned user is back in twenty seconds with x@y.com). Gating anything
  # on it needs a "confirm your email" screen in both clients first —
  # docs/EMAIL_CONFIRMATION.md.
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :validatable, :trackable

  include DeviseTokenAuth::Concerns::User
  include ClientVersionReporting

  has_one_attached :avatar

  # The avatar was unvalidated: `user[avatar]` accepted any file of any size.
  # Smaller cap than a listing photo — this is one small square, and the mobile
  # uploader already compresses it to JPEG before sending.
  MAX_AVATAR_SIZE = 5.megabytes
  validates :avatar,
            attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: MAX_AVATAR_SIZE }

  enum :status, { active: 0, suspended: 1, banned: 2 }

  has_many :listings, dependent: :destroy
  # SHOP-1 (docs/SHOPS.md in hatiwal-mobile). Owned shops go with the account;
  # memberships are the right to sell AS a shop. `active_shop` is who the user
  # sells as ("Selling as"); nil = Me. Always read it through #selling_shop.
  has_many :owned_shops, class_name: Shop.name, foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner
  has_many :shop_members, dependent: :destroy
  has_many :shops, through: :shop_members
  belongs_to :active_shop, class_name: Shop.name, optional: true
  has_many :saved_listings, dependent: :destroy
  has_many :saved_listing_items, through: :saved_listings, source: :listing
  has_many :hidden_listings, dependent: :destroy
  has_many :hidden_listing_entries, through: :hidden_listings, source: :listing
  has_many :buyer_conversations, class_name: Conversation.name, foreign_key: :buyer_id, dependent: :destroy, inverse_of: :buyer
  has_many :seller_conversations, class_name: Conversation.name, foreign_key: :seller_id, dependent: :destroy, inverse_of: :seller
  has_many :messages, dependent: :destroy
  has_many :filed_reports, class_name: Report.name, foreign_key: :reporter_id, dependent: :destroy, inverse_of: :reporter
  has_many :blocks_as_blocker, class_name: Block.name, foreign_key: :blocker_id, dependent: :destroy, inverse_of: :blocker
  has_many :blocks_as_blocked, class_name: Block.name, foreign_key: :blocked_id, dependent: :destroy, inverse_of: :blocked
  has_many :blocked_users, through: :blocks_as_blocker, source: :blocked
  has_many :blocking_users, through: :blocks_as_blocked, source: :blocker
  has_many :saved_searches, dependent: :destroy
  has_many :listing_views, dependent: :destroy
  has_many :viewed_listings, through: :listing_views, source: :listing
  has_many :warnings, class_name: "UserWarning", dependent: :destroy
  has_many :admin_emails, class_name: AdminEmail.name, dependent: :destroy
  has_many :admin_outreaches, class_name: AdminOutreach.name, dependent: :destroy
  has_many :reviews_written, class_name: Review.name, foreign_key: :reviewer_id, dependent: :destroy, inverse_of: :reviewer
  has_many :reviews_received, class_name: Review.name, foreign_key: :reviewee_id, dependent: :destroy, inverse_of: :reviewee

  # ── VER-1: applying for the Verified badge (hatiwal-mobile/docs/VERIFICATION.md) ──
  has_many :verification_requests, as: :subject, dependent: :destroy, inverse_of: :subject

  # The latest application that still means something (a cancelled one does not).
  def latest_verification_request
    verification_requests.where.not(status: :cancelled).order(created_at: :desc, id: :desc).first
  end

  # What stops this person applying, as stable keys the clients translate.
  # Empty = may apply.
  # Owner rule (1.1.6): opening a shop and applying for Verified need a
  # CONFIRMED email, or the address may be wrong. Google sign-in sets
  # confirmed_at (the address is proven by Google).
  def email_confirmed? = confirmed_at.present?

  def verification_missing
    missing = []
    missing << "email_confirmed" if confirmed_at.blank?
    missing << "avatar" unless avatar.attached?
    missing << "full_name" if firstname.blank? || lastname.blank?
    missing
  end

  # A verified person who changes their name loses the badge: it vouched for
  # the OLD name. They re-apply (the status card says "Your name changed —
  # verify again", VerificationStatus#name_changed?). Decided rows are history
  # and stay exactly as they were. Called from the user's own profile edit,
  # not on admin edits.
  def drop_badge_after_name_change!
    return unless verified? && (saved_change_to_firstname? || saved_change_to_lastname?)

    update!(verified: false)
  end

  # Account deletion: nothing of an ID document may outlive the account. Open
  # requests are cancelled (so none sits in the admin queue forever), every
  # photo is deleted, and the name on the document + the number are blanked.
  # Decisions and the number's digest stay (ban evasion), nothing readable.
  def forget_verification_documents!
    verification_requests.find_each do |request|
      request.purge_files!
      # The number goes; its digest stays (with the decision), so a banned
      # person cannot verify a new account with the same ID.
      attrs = { name_on_document: nil, document_number: nil, document_last4: nil, updated_at: Time.current }
      attrs.merge!(status: VerificationRequest.statuses[:cancelled], decided_at: Time.current) if request.requested?
      request.update_columns(attrs)
    end
  end
  # ── SHOP-1: the subject hooks VerificationRequest calls (a Shop has the same) ──
  def verification_granted!(_admin) = update!(verified: true)
  def verification_withdrawn! = update!(verified: false)
  def verification_notice_recipient = self
  def verification_notice_key(decision) = { verified: :user_verified, rejected: :user_verification_rejected, revoked: :user_badge_revoked }.fetch(decision)
  # ── end VER-1 ──

  validates :firstname, presence: true
  validates :lastname, presence: true
  # The locales the app ships. Extracted from the validation below so the admin
  # filter reads the same list rather than keeping its own copy that can drift.
  SUPPORTED_LANGUAGES = %w[en ps fa ur].freeze

  validates :preferred_language, inclusion: { in: SUPPORTED_LANGUAGES }, allow_blank: true
  validates :preferred_theme, inclusion: { in: %w[light dark system] }, allow_blank: true
  validates :push_token, length: { maximum: 200 }, allow_blank: true
  # A WhatsApp number, which is often NOT the account phone (different SIM).
  #
  # Length only — deliberately no format check. Afghan numbers are written
  # +93 70 …, 0093…, 070… and 70… interchangeably, and the clients normalise to
  # digits when building the wa.me link (mobile: src/utils/whatsapp.ts). A
  # regex here would reject numbers people actually have, and it is not the
  # server's place to decide which spelling of a real number is allowed.
  validates :whatsapp_number, length: { maximum: 30 }, allow_blank: true
  validate :away_until_must_be_future, if: -> { away_until.present? }

  # Self-deleted (anonymized) accounts are hidden from public profiles + search.
  scope :not_deleted, -> { where(deleted_at: nil) }
  # Hidden from public surfaces (profile, search) both while pending deletion
  # and after final anonymization.
  scope :publicly_active, -> { where(deleted_at: nil, deletion_scheduled_at: nil) }

  def full_name
    "#{firstname} #{lastname}".strip
  end

  # The single "Hatiwal Support" account that support threads are held with.
  # Admin replies are posted AS this user (Message#admin_user records who wrote
  # them). Created on first use rather than by a migration or seed: the account
  # on its own is invisible to every client, and creating it never creates a
  # conversation.
  #
  # `verified: true` is DELIBERATE, so clients render the verified badge on
  # Support. The email uses the reserved `.invalid` TLD: this account never
  # signs in and must never be sent mail. The password is random and discarded.
  SUPPORT_ACCOUNT_EMAIL = "support@hatiwal.invalid".freeze

  # Declared for the same reason as Conversation's `kind`: SendMessagePushJob
  # asks `support_account?` on EVERY push, so if this column were missing
  # (code ahead of its migration) every chat push would fail. Declared, it
  # reads false.
  attribute :support_account, :boolean, default: false

  # Whether an admin may email this user. `.invalid` covers both the Support
  # account (support@hatiwal.invalid) and anonymized deleted accounts
  # (deleted-<id>@deleted.invalid) — addresses that exist only to fill the column.
  def emailable?
    email_refusal_reason.nil?
  end

  def email_refusal_reason
    return "the Support account" if support_account?
    return "the account is deleted" if deleted_at.present?
    return "no email address" if email.blank?

    "a placeholder address" if email.end_with?(".invalid")
  end

  # Signed, non-expiring id for the one-click unsubscribe link (RFC 8058 links
  # must keep working). The page offers an undo, since anyone holding a
  # forwarded email could otherwise opt this user out for good.
  UNSUBSCRIBE_PURPOSE = :email_unsubscribe

  # Real people: everyone except the Support account, which would otherwise be
  # counted as a new signup in the growth charts.
  scope :members, -> { where(support_account: false) }

  def self.support_account!
    find_by(support_account: true) || create_support_account!
  end

  def self.create_support_account!
    password = SecureRandom.base58(32)
    user = new(firstname: "Hatiwal", lastname: "Support", email: SUPPORT_ACCOUNT_EMAIL,
               password: password, password_confirmation: password,
               verified: true, support_account: true)
    user.skip_confirmation!
    user.save!
    user
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Lost a race with a concurrent first use: the partial unique index (or the
    # email uniqueness check) means the other request created it.
    find_by!(support_account: true)
  end
  private_class_method :create_support_account!

  # Refresh the denormalized rating aggregates from this user's VISIBLE reviews
  # (as reviewee). Called only when a review is revealed, so feeds never sum
  # reviews per row. update_columns skips validations/callbacks by design.
  def recompute_review_stats!
    visible = Review.visible.for_reviewee(self)
    update_columns(
      review_count: visible.count,
      avg_rating: visible.average(:rating)&.round(2)
    )
  end

  # Refresh the denormalized sold_count / bought_count (TASK-TX02) from
  # source data — a safety net for `bin/rails transactions:recompute_counters`
  # (see lib/tasks/transactions.rake) rather than something the normal
  # reserve/sold flow needs to call. Normal operation bumps these counters
  # incrementally via Transaction#bump_trust_counters! (and decrementally via
  # Transaction#void!/#correct!, SF-B4); this method recomputes
  # them from scratch instead, so it also repairs any drift caused by a path
  # that bypasses those — e.g. an admin directly editing a Listing's `status`
  # via the Administrate dashboard (ListingDashboard::FORM_ATTRIBUTES permits
  # `:status`, which skips Listing#sold_with_buyer!/#sold! entirely).
  #
  # Mirrors the two-source GREATEST(...) logic in
  # db/migrate/20260809000000_add_transaction_stats_to_users.rb: sold_count is
  # the larger of the real transactions-table count and the legacy
  # listings.sold count, since a pre-TX01 (or buyer-less) sale is only
  # reflected in the latter. update_columns skips validations/callbacks by
  # design, same as recompute_review_stats! above.
  #
  # Review fix (TASK-TX02, MED — "distinct listings, not raw Transaction
  # rows"): counts DISTINCT listing_id, not a raw row count. The admin
  # dashboard bypass documented on Transaction#bump_trust_counters! really can
  # create a SECOND sold Transaction for the same listing (ListingDashboard
  # permits :status directly, so an admin can flip a sold Listing back to
  # active/reserved and the mobile seller can then complete the sale again).
  # That bypass is real and this recompute is the only repair path for it —
  # counting distinct listings means one listing's sale is always worth
  # exactly 1 toward the count no matter how many Transaction rows it
  # accumulated, so re-running this task after the bypass restores the
  # correct figure. The LIVE incremental bump (`bump_trust_counters!`) still
  # over-counts by +1 per extra sold Transaction until this task is re-run —
  # there is no live decrement path — so this recompute is a genuine repair
  # lever, not a no-op.
  def recompute_transaction_counters!
    sold_from_transactions = Transaction.as_seller(self).sold.distinct.count(:listing_id)
    sold_from_legacy_listings = listings.sold.count
    update_columns(
      sold_count: [ sold_from_transactions, sold_from_legacy_listings ].max,
      bought_count: Transaction.as_buyer(self).sold.distinct.count(:listing_id)
    )
  end

  def blocked?(other_user)
    blocked_users.exists?(other_user.id)
  end

  def blocked_by?(other_user)
    blocking_users.exists?(other_user.id)
  end

  # ── Account moderation (admin block) ─────────────────────────────────────────
  #
  # NOTE: `blocked?(other_user)` above is user-to-user blocking. The methods here
  # are about an ADMIN suspending/banning the whole account. A blocked account
  # cannot log in (active_for_authentication?) and is rejected on authenticated
  # requests (Api::V1::Base#reject_blocked_user!), always with a clear message.

  def account_blocked?
    suspended? || banned?
  end

  # True once the user self-deletes (account anonymized + login blocked).
  def deleted?
    deleted_at.present?
  end

  # In the 30-day grace window: deletion requested but not yet finalized. The
  # account is hidden from others and logged out, but the user can still log in
  # to restore it. (active_for_authentication? deliberately does NOT block this
  # — that is what lets them come back and cancel.)
  def pending_deletion?
    deletion_scheduled_at.present? && deleted_at.nil?
  end

  # Devise/devise_token_auth call this during sign-in; returning false blocks the
  # login and surfaces `inactive_message` to the client.
  def active_for_authentication?
    super && !account_blocked? && !deleted?
  end

  # The device changing the password (its devise_token_auth client id). Set by
  # Api::V1::Auth::PasswordsController#update.
  attr_accessor :password_change_client

  # A password change keeps ONLY the device that made it. devise_token_auth's
  # default keeps the token with the latest expiry, and with SessionKeepAlive
  # that is simply the most recently active device, which can be the leaked
  # token the change is meant to kill.
  def remove_tokens_after_password_reset
    return super unless should_remove_tokens_after_password_reset? && password_change_client.present? && tokens.present?

    self.tokens = tokens.slice(password_change_client)
  end

  # Devise sends its notifications with deliver_now, which would put an SMTP
  # round-trip inside the signup request and — worse — turn a mail failure into a
  # 500 on an account that was actually created. Queue them instead.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  def inactive_message
    return :account_deleted if deleted?

    account_blocked? ? :"account_#{status}" : super
  end

  # Human-readable "you are blocked" message. Always states they are blocked;
  # when the admin gave a reason, it is appended ("… Reason: <reason>"). The bare
  # reason is also returned separately for clients that want it structured.
  def account_block_message
    return unless account_blocked?

    base = I18n.t("accounts.blocked.#{status}", default: I18n.t("accounts.blocked.default"))
    return base if block_reason.blank?

    "#{base} #{I18n.t('accounts.blocked.reason', reason: block_reason)}"
  end

  # ── Self-deletion (anonymize, keep history) ──────────────────────────────────
  #
  # App Store 5.1.1(v) / Google Play require in-app account deletion. We strip all
  # personal data and block login, but DO NOT destroy the user's messages — they
  # are retained as "Deleted user" so the other party keeps their conversation.
  # Their active listings are soft-removed (hidden from the feed, kept for the
  # conversation reference). All auth tokens are cleared, ending every session.
  # How long a self-deleted account can still be recovered before it is
  # permanently anonymized by FinalizeAccountDeletionsJob.
  DELETION_GRACE_PERIOD = 30.days

  # Step 1 of deletion: schedule it. The account immediately becomes inaccessible
  # to others (listings pulled from the feed) and every session is ended, but the
  # data is left intact so logging back in within the grace period can restore it.
  def schedule_deletion!
    transaction do
      listings.where(removed_at: nil)
              .update_all(removed_at: Time.current, removed_reason: "pending_deletion", updated_at: Time.current)
      update!(deletion_scheduled_at: Time.current, tokens: {})
    end
  end

  # Undo a scheduled deletion (user logged back in within the grace period):
  # restore the listings we pulled and clear the schedule.
  def cancel_deletion!
    return false unless pending_deletion?

    transaction do
      listings.where(removed_reason: "pending_deletion")
              .update_all(removed_at: nil, removed_reason: nil, updated_at: Time.current)
      update!(deletion_scheduled_at: nil)
    end
    true
  end

  # Step 2 of deletion (the finalizer, run by FinalizeAccountDeletionsJob once the
  # grace period has elapsed — or directly for an immediate hard delete): strip
  # all PII and block login permanently, while RETAINING messages as "Deleted
  # user" so the other participant keeps their conversation history.
  def anonymize_account!
    transaction do
      # Hide active listings from the public feed but keep them for chat history.
      listings.where(removed_at: nil)
              .update_all(removed_at: Time.current, removed_reason: "account_deleted", updated_at: Time.current)

      assign_attributes(
        firstname: "Deleted",
        lastname: "user",
        email: "deleted-#{id}@deleted.invalid",
        uid: "deleted-#{id}@deleted.invalid",
        phone: nil,
        bio: nil,
        city: nil,
        province: nil,
        latitude: nil,
        longitude: nil,
        guessed_latitude: nil,
        guessed_longitude: nil,
        guessed_province: nil,
        guessed_source: nil,
        guessed_at: nil,
        push_token: nil,
        password: SecureRandom.hex(32), # unusable; old credentials no longer work
        deleted_at: Time.current,
        tokens: {}                       # invalidate all existing sessions
      )
      avatar.purge_later if avatar.attached?
      forget_verification_documents! # VER-1
      # SHOP-1: their shops leave with them; memberships elsewhere end.
      owned_shops.where.not(status: :closed).find_each(&:close!)
      shop_members.destroy_all
      assign_attributes(active_shop_id: nil)
      assign_attributes(verified: false)
      save!(validate: false)
    end
  end

  # ── Warning / strike system ──────────────────────────────────────────────────
  #
  # Warnings accumulate; once WARNING_BLOCK_THRESHOLD are active at once the user
  # is auto-suspended. Each warning is active for Warning::ACTIVE_PERIOD then
  # decays, so good behavior over time lowers the count and (via the daily
  # reinstate job) lifts an auto-suspension. Severe cases are still blocked
  # directly by an admin, bypassing warnings.
  WARNING_BLOCK_THRESHOLD = 3

  def active_warnings
    warnings.active
  end

  def active_warnings_count
    active_warnings.count
  end

  def warnings_remaining
    [ WARNING_BLOCK_THRESHOLD - active_warnings_count, 0 ].max
  end

  # Issue a strike. Creates the warning and auto-suspends the user if this pushes
  # their active warnings to the threshold. Returns the created Warning.
  def issue_warning!(reason:, admin_user: nil, category: :other)
    warning = warnings.create!(admin_user: admin_user, reason: reason, category: category)
    auto_suspend_for_strikes! if active? && active_warnings_count >= WARNING_BLOCK_THRESHOLD
    warning
  end

  # Lift an auto-suspension once warnings have decayed below the threshold. Only
  # touches auto-blocks — manual suspensions/bans are left for an admin to undo.
  def reinstate_if_decayed!
    return false unless suspended? && auto_blocked?
    return false if active_warnings_count >= WARNING_BLOCK_THRESHOLD

    update!(status: :active, auto_blocked: false, block_reason: nil)
    true
  end

  # Clean slate — expire all active warnings (used when an admin manually
  # unblocks a user, giving them a fresh start).
  def clear_active_warnings!
    active_warnings.update_all(expires_at: Time.current)
  end

  # Reports filed AGAINST this user — either directly, or against one of their
  # listings. Used on the admin user page so moderators see incoming reports.
  def reports_against
    Report.where(reportable: self)
          .or(Report.where(reportable_type: Listing.name, reportable_id: listings.select(:id)))
          .order(created_at: :desc)
  end

  def conversations
    Conversation.where("buyer_id = ? OR seller_id = ?", id, id)
  end

  # ── Away mode ────────────────────────────────────────────────────────────────
  #
  # Seller-set temporary status. away_until stores a future datetime; the column
  # is never auto-cleared (a stale past date is equivalent to not away — the
  # predicate gates display so a past date never surfaces to buyers).
  #
  #   away? → true only when away_until is a future datetime
  #
  def away?
    away_until.present? && away_until.future?
  end

  # ── Last-active recency label ─────────────────────────────────────────────────
  #
  # Privacy-safe coarse bucket derived from last_sign_in_at. Never exposes the
  # raw timestamp to public callers; the serializer receives a symbol or nil.
  #
  # Returns:
  #   :today       — signed in within the last 24 hours
  #   :this_week   — signed in within the last 7 days (but not today)
  #   :this_month  — signed in within the last 30 days (but not this week)
  #   nil          — no sign-in on record, or last sign-in was more than 30 days ago
  def last_active_label
    return nil if last_sign_in_at.nil?

    elapsed = Time.current - last_sign_in_at
    if elapsed < 24.hours
      :today
    elsif elapsed < 7.days
      :this_week
    elsif elapsed < 30.days
      :this_month
    end
  end

  # ── Response rate ────────────────────────────────────────────────────────────
  #
  # All response-rate logic is driven by a single memoized computation
  # (seller_response_stats) so the database query runs AT MOST ONCE per
  # request/object — regardless of how many times the serializer calls
  # response_rate_percent or response_time_label.
  #
  # Public helpers:
  #
  #   response_rate_percent  → Integer 0-100, or nil (threshold not met)
  #   response_time_label    → Symbol (:within_one_hour / :within_a_day /
  #                            :within_a_few_days), or nil (threshold not met)

  ResponseStats = Data.define(:rate_percent, :time_label)

  def response_rate_percent
    seller_response_stats.rate_percent
  end

  def response_time_label
    seller_response_stats.time_label
  end

  # What GET /listings?user_id= returns (`browsable` = live + not expired).
  def live_listings_count
    @live_listings_count ||= listings.live.not_expired.count
  end

  # ── Shareable deep-link URL ──────────────────────────────────────────────────
  # Returns an https profile share URL when PUBLIC_SHARE_BASE_URL env var is
  # configured, otherwise nil (the mobile app falls back to hatiwal://seller/<id>).
  # No hardcoded host in committed code — all infra config lives in .env / secrets.
  def self.profile_share_url_for(user)
    base = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    return nil if base.blank?

    "#{base.chomp('/')}/u/#{user.id}"
  end

  def self.search_by_name(query)
    return publicly_active if query.blank?

    words = query.to_s.strip.split(/\s+/)
    result = publicly_active

    words.each do |word|
      term = "%#{word.downcase}%"
      result = result.where(
        "LOWER(firstname) LIKE ? OR LOWER(lastname) LIKE ?",
        term, term
      )
    end

    result
  end

  # ── LOC-1: own address + guessed location ───────────────────────────────────
  # (hatiwal-mobile/docs/USER_LOCATION.md)
  #
  # OWN address: latitude/longitude/province/city — set by the user only.
  # GUESSED location: guessed_* — learned from what the user does; the newest
  # clue replaces the last. A guess NEVER overwrites the own address, and is
  # never in a public serializer.
  #
  # The rule, own → guess → Kabul, lives HERE only. Clients read the result from
  # `location` in the :me view and never re-implement it.
  module LocationSource
    OWN = "own"
    GUESS = "guess"
    DEFAULT = "default"
  end

  module GuessSource
    LISTING = "listing"
    SEARCH_AREA = "search_area"
    GPS = "gps"
    ALL = [ LISTING, SEARCH_AREA, GPS ].freeze
  end

  # The own address as a point inside the countries we serve, or nil: the saved
  # map point when it is inside, else the capital of the province (or of a
  # province written as the city). An address abroad counts as no address.
  def own_location
    if ServiceArea.include?(latitude, longitude)
      return { latitude: latitude.to_f, longitude: longitude.to_f,
               province: province.presence || ServiceArea.nearest_province(latitude, longitude) }
    end

    name = [ province, city ].find { |v| ServiceArea.province_center(v) }
    return nil unless name

    lat, lng = ServiceArea.province_center(name)
    { latitude: lat, longitude: lng, province: name }
  end

  def own_location?
    own_location.present?
  end

  def guessed_location
    return nil unless ServiceArea.include?(guessed_latitude, guessed_longitude)

    { latitude: guessed_latitude.to_f, longitude: guessed_longitude.to_f, province: guessed_province }
  end

  # own → guess → Kabul, with which one was used.
  def effective_location
    if (own = own_location)
      own.merge(source: LocationSource::OWN)
    elsif (guess = guessed_location)
      guess.merge(source: LocationSource::GUESS)
    else
      ServiceArea::DEFAULT.merge(source: LocationSource::DEFAULT)
    end
  end

  # Records a clue about where the user is. Returns true when it was saved,
  # false when it was ignored: the user has an own address, the source is not
  # one we know, or the point is outside Afghanistan/Pakistan/Iran.
  def record_location_guess!(latitude:, longitude:, source:, province: nil)
    return false unless GuessSource::ALL.include?(source.to_s)
    return false unless ServiceArea.include?(latitude, longitude)
    return false if own_location?

    named = ServiceArea.province_center(province) ? province.to_s.strip : nil
    update_columns(
      guessed_latitude: latitude.to_f.round(6),
      guessed_longitude: longitude.to_f.round(6),
      guessed_province: named || ServiceArea.nearest_province(latitude, longitude),
      guessed_source: source.to_s,
      guessed_at: Time.current
    )
    true
  end

  # ── SHOP-1: "Selling as" ────────────────────────────────────────────────────
  # The shop this user is selling as, or nil for Me. Checked against the
  # membership AND the shop's status on every call, so a stored choice can never
  # act for a shop the user has left, or one that was suspended or deleted; a
  # stale choice is cleared and the user falls back to Me.
  def selling_shop
    return nil if active_shop_id.nil?

    shop = active_shop
    return shop if shop&.active? && shop.member?(self)

    update_column(:active_shop_id, nil)
    nil
  end

  # Switch who the user sells as. nil = Me. Returns false (and changes nothing)
  # for a shop they are not a member of, or one that is not active.
  def sell_as!(shop)
    return false if shop && !(shop.active? && shop.member?(self))

    update!(active_shop: shop)
  end

  # Unread messages per identity, in ONE grouped query, for the "Selling as"
  # pill and sheet: { buying:, selling_me:, shops: { shop_id => n } }. Same
  # rules as unread_message_count (archived chats are silent; your own
  # messages never count). A support thread has no listing and counts as buying.
  def unread_counts
    identity = Arel.sql(
      "CASE WHEN conversations.buyer_id = #{id.to_i} THEN 'buying' " \
      "WHEN conversations.shop_id IS NOT NULL THEN conversations.shop_id::text ELSE 'selling_me' END"
    )
    raw = Message.joins(:conversation)
                 .where(conversation_id: Conversation.for_user(self).not_archived_for(self).select(:id), read_at: nil)
                 .where(Conversation.inbound_message_sql_for(self), u: id)
                 .group(identity).count
    shops = raw.except("buying", "selling_me").transform_keys(&:to_s)
    { buying: raw.fetch("buying", 0), selling_me: raw.fetch("selling_me", 0), shops: shops }
  end

  # The seller-side listings for whoever the user is selling as: the shop's
  # products, or their personal (shop-less) listings as Me.
  # Listings this user may manage: their own, plus (SHOP-3) every product of a
  # shop they're a member of.
  def manageable_listings
    Listing.where(user_id: id).or(Listing.where(shop_id: shop_members.select(:shop_id)))
  end

  def listings_for_selling_identity
    shop = selling_shop
    # SHOP-3: a shop's products are every member's to manage, whoever posted them.
    shop ? shop.listings : listings.where(shop_id: nil)
  end

  private

  def away_until_must_be_future
    return if away_until.blank?

    errors.add(:away_until, :not_in_future, message: "must be in the future") unless away_until.future?
  end

  def auto_suspend_for_strikes!
    update!(
      status: :suspended,
      auto_blocked: true,
      block_reason: I18n.t(
        "accounts.auto_suspended_reason",
        count: WARNING_BLOCK_THRESHOLD,
        default: "Automatically suspended after reaching #{WARNING_BLOCK_THRESHOLD} warnings."
      )
    )
  end

  # Loads the seller's recent conversations exactly once and derives both
  # the rate percentage and the time-label bucket in a single pass.
  # The result is memoized on the model instance for the lifetime of the
  # object, preventing duplicate queries when the serializer reads both
  # attributes in the same request.
  def seller_response_stats
    @seller_response_stats ||= compute_seller_response_stats
  end

  # A LIST of public profiles (GET /blocks) in a fixed number of queries: the
  # response stats from one window query for all of them, and the live listing
  # counts from one grouped count. Each user then reads its own memo, so the
  # serializer stays the same for one profile and for many.
  def self.preload_public_stats(users)
    users = Array(users)
    return users if users.empty?

    ids = users.map(&:id)
    convos = Conversation.where(seller_id: ids, created_at: 90.days.ago..).includes(:messages).group_by(&:seller_id)
    counts = Listing.where(user_id: ids).live.not_expired.group(:user_id).count
    users.each do |u|
      u.instance_variable_set(:@seller_response_stats, u.send(:compute_seller_response_stats, convos.fetch(u.id, [])))
      u.instance_variable_set(:@live_listings_count, counts.fetch(u.id, 0))
    end
  end

  def compute_seller_response_stats(preloaded = nil)
    window_convos = preloaded || seller_conversations
                                 .where(created_at: 90.days.ago..)
                                 .includes(:messages)
                                 .to_a # materialise once; all further work is in-memory

    if window_convos.size < 5
      return ResponseStats.new(rate_percent: nil, time_label: nil)
    end

    replied_count  = 0
    response_times = []

    window_convos.each do |conv|
      buyer_msgs  = conv.messages.select { |m| m.user_id == conv.buyer_id }
      seller_msgs = conv.messages.select { |m| m.user_id == id }

      first_buyer_msg = buyer_msgs.min_by(&:created_at)
      next unless first_buyer_msg

      # Seller messages that arrived AFTER the first buyer message
      seller_replies = seller_msgs.select { |sm| sm.created_at > first_buyer_msg.created_at }
      first_reply    = seller_replies.min_by(&:created_at)

      if first_reply
        elapsed = first_reply.created_at - first_buyer_msg.created_at
        response_times << elapsed
        replied_count += 1 if elapsed <= 24.hours
      end
    end

    rate_percent = (replied_count.to_f / window_convos.size * 100).round

    # A seller who never replied to any buyer's first message must NOT show a
    # reassuring "responds within…" badge — that would be a false trust signal.
    # Return nil so the mobile screens hide the badge entirely for such sellers.
    time_label =
      if response_times.empty?
        nil
      else
        sorted = response_times.sort
        median = sorted[sorted.size / 2]
        if median <= 1.hour
          :within_one_hour
        elsif median <= 24.hours
          :within_a_day
        else
          :within_a_few_days
        end
      end

    ResponseStats.new(rate_percent: rate_percent, time_label: time_label)
  end
end
