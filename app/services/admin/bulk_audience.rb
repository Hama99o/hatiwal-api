# Who a bulk email will actually reach, from a filtered user relation — and,
# just as important, who it won't and why. Nothing is excluded silently: every
# exclusion is counted and shown before sending.
#
#   matched     the filtered segment (real members only)
#   unconfirmed email never proven — bounces are what get a sender throttled
#   opted_out   unsubscribed from bulk email
#   unreachable deleted accounts / placeholder addresses
#   recipients  everyone left
class Admin::BulkAudience
  def initialize(relation)
    @matched = relation.merge(User.members)
  end

  def matched_count = @matched.count
  def unconfirmed_count = @matched.where(confirmed_at: nil).count
  def opted_out_count = @matched.where.not(confirmed_at: nil).where.not(email_opt_out_at: nil).count
  def unreachable_count = reachable_base.count - recipients.count

  def recipients
    reachable_base.where(deleted_at: nil).where.not("users.email LIKE ?", "%.invalid")
  end

  def recipients_count = recipients.count

  # Recipients per preferred_language, every supported language listed.
  def by_language
    counts = recipients.group(:preferred_language).count
    AdminBulkEmail::LOCALES.index_with { |loc| counts.fetch(loc, 0) }
                           .merge("other" => counts.except(*AdminBulkEmail::LOCALES).values.sum)
  end

  # ── In-app (no email confirmation needed; the gate decides) ──────────────
  # Every member in the segment who isn't deleted.
  def in_app_base = @matched.where(deleted_at: nil)

  # Passes the support gate (has a thread already, or SUPPORT_ADMIN_INITIATE).
  def in_app_allowed
    return in_app_base if Conversation.admin_initiate_enabled?

    in_app_base.where(id: Conversation.person_support.select(:buyer_id))
  end

  def in_app_blocked_count = in_app_base.count - in_app_allowed.count

  # Got an in-app broadcast within the cooldown — excluded, and counted.
  def in_app_recent_ids
    AdminBulkInAppDelivery.recent_sent(AdminBulkEmail::IN_APP_COOLDOWN.ago).select(:user_id)
  end

  def in_app_cooled_count = in_app_allowed.where(id: in_app_recent_ids).count

  def in_app_recipients = in_app_allowed.where.not(id: in_app_recent_ids)
  def in_app_recipients_count = in_app_recipients.count

  # Archived/deleted Support: delivered quietly, never pushed.
  def in_app_muted_count
    in_app_recipients.where(id: Conversation.person_support.where("buyer_archived_at IS NOT NULL OR buyer_deleted_at IS NOT NULL")
                                                       .select(:buyer_id)).count
  end

  # Could get a push at all (holds a token and hasn't muted Support).
  def in_app_push_reachable_count
    muted = Conversation.person_support.where("buyer_archived_at IS NOT NULL OR buyer_deleted_at IS NOT NULL").select(:buyer_id)
    in_app_recipients.where.not(push_token: [ nil, "" ]).where.not(id: muted).count
  end

  # Recipients who haven't reported a new app version — on v1.0.4 the message
  # arrives but the Support chat looks like a removed-listing chat. Shown, never blocking.
  def in_app_old_app_count = in_app_recipients.where(last_app_version: nil).count

  def in_app_by_language
    counts = in_app_recipients.group(:preferred_language).count
    AdminBulkEmail::LOCALES.index_with { |loc| counts.fetch(loc, 0) }
                           .merge("other" => counts.except(*AdminBulkEmail::LOCALES).values.sum)
  end

  # Readers per language among the people the chosen channels reach.
  def reached_by_language(email:, in_app:)
    counts = User.where(id: reached(email: email, in_app: in_app)).group(:preferred_language).count
    AdminBulkEmail::LOCALES.index_with { |loc| counts.fetch(loc, 0) }
                           .merge("other" => counts.except(*AdminBulkEmail::LOCALES).values.sum)
  end

  # People reached by the chosen channels (someone on both counts once) —
  # the number the admin types to confirm.
  def reached(email:, in_app:)
    ids = []
    ids |= recipients.pluck(:id) if email
    ids |= in_app_recipients.pluck(:id) if in_app
    ids
  end

  private

  # Confirmed and not opted out.
  def reachable_base
    @matched.where.not(confirmed_at: nil).where(email_opt_out_at: nil)
  end
end
