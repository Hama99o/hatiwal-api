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

  has_one_attached :avatar

  # The avatar was unvalidated: `user[avatar]` accepted any file of any size.
  # Smaller cap than a listing photo — this is one small square, and the mobile
  # uploader already compresses it to JPEG before sending.
  MAX_AVATAR_SIZE = 5.megabytes
  validates :avatar,
            attached_file: { types: AttachedFileValidator::IMAGE_TYPES, max_size: MAX_AVATAR_SIZE }

  enum :status, { active: 0, suspended: 1, banned: 2 }

  has_many :listings, dependent: :destroy
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
  has_many :reviews_written, class_name: Review.name, foreign_key: :reviewer_id, dependent: :destroy, inverse_of: :reviewer
  has_many :reviews_received, class_name: Review.name, foreign_key: :reviewee_id, dependent: :destroy, inverse_of: :reviewee

  validates :firstname, presence: true
  validates :lastname, presence: true
  validates :preferred_language, inclusion: { in: %w[en ps fa] }, allow_blank: true
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
        push_token: nil,
        password: SecureRandom.hex(32), # unusable; old credentials no longer work
        deleted_at: Time.current,
        tokens: {}                       # invalidate all existing sessions
      )
      avatar.purge_later if avatar.attached?
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

  def compute_seller_response_stats
    window_convos = seller_conversations
                    .where(created_at: 90.days.ago..)
                    .includes(:messages)
                    .to_a   # materialise once; all further work is in-memory

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
