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

  private

  # Confirmed and not opted out.
  def reachable_base
    @matched.where.not(confirmed_at: nil).where(email_opt_out_at: nil)
  end
end
