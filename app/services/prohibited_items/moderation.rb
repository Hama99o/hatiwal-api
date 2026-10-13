# An admin's decision on a Flag (owner, 2026-10-13, option B: ALL MANUAL):
#
#   dismiss!               nothing wrong: the flag closes, the reports behind it
#                          are dismissed, nothing is said to the seller.
#   take_down!             a listing goes back to the seller's drafts (any open
#                          hold cancelled); a shop is suspended through the
#                          existing Shop#suspend!. The seller / owner is told
#                          why in Support, in their language.
#   take_down!(warn: true) the same, plus a strike through the existing
#                          User#issue_warning! (3 active warnings = suspended,
#                          User::WARNING_BLOCK_THRESHOLD; not re-implemented).
#
# Decided under the flag's row lock: a double-click or a second admin gets
# Refused, never a second warning or message.
class ProhibitedItems::Moderation
  class Refused < StandardError; end

  attr_reader :flag, :admin, :note

  def initialize(flag, admin:, note: nil, category: nil)
    @flag = flag
    @admin = admin
    @note = note.to_s.strip.presence
    @category = category.to_s.presence_in(ProhibitedTerm::CATEGORIES.keys.map(&:to_s))
  end

  # The category the decision is filed under: the admin's pick, else the
  # flag's own, else "other" (a report-only flag has none).
  def category
    @category || flag.category || "other"
  end

  def dismiss!
    decide!(:dismissed, "dismiss") do
      flag.reports.where(status: %i[pending reviewed]).update_all(status: Report.statuses[:dismissed], updated_at: Time.current)
    end
  end

  def take_down!(warn: false)
    decide!(:actioned, warn ? "take_down_warn" : "take_down") do
      warnings = warn ? issue_warning! : nil
      flag.listing? ? take_down_listing!(warnings) : take_down_shop!(warnings)
      flag.reports.where(status: %i[pending reviewed]).update_all(status: Report.statuses[:resolved], updated_at: Time.current)
    end
  end

  private

  def decide!(status, action)
    flag.with_lock do
      raise Refused, "This flag was already decided (#{flag.status})." unless flag.open?
      raise Refused, "The flagged #{flag.flaggable_type.downcase} no longer exists." if flag.flaggable.nil?

      yield
      flag.update!(status: status, action_taken: action, acted_by: admin, acted_at: Time.current,
                   note: note, category: status == :dismissed ? flag.category : category)
    end
    flag
  end

  def issue_warning!
    user = flag.responsible_user
    raise Refused, "No user to warn." unless user

    user.issue_warning!(admin_user: admin, category: :prohibited_item,
                        reason: "Prohibited item (#{category.humanize.downcase}): #{flag.flaggable_label} (flag ##{flag.id})")
    user.active_warnings_count
  end

  # Back to drafts while live; a sold listing (not live, not a draft) is
  # soft-removed instead, the existing admin take-down. The seller is told
  # either way.
  def take_down_listing!(warnings)
    listing = flag.flaggable
    if listing.live?
      listing.move_to_draft_for_moderation!
    elsif !listing.draft?
      listing.take_down!(reason: "Prohibited item: #{category.humanize.downcase}")
    end
    SupportNoticeJob.enqueue_prohibited(listing, :listing_prohibited_removed, category: category, note: note, warnings: warnings)
  end

  # Shops are taken down the way an admin already suspends one (Shop#suspend!:
  # hidden from search, the team sells as themselves, the owner is told in the
  # shop's Support thread). The reason carries the category and the link.
  def take_down_shop!(warnings)
    shop = flag.flaggable
    raise Refused, "#{shop.name} is closed by its owner: there is nothing to take down." if shop.closed?
    return if shop.suspended?

    locale = SupportNoticeJob.prohibited_locale(shop.owner)
    shop.suspend!(reason: SupportNoticeJob.prohibited_shop_reason(category, locale: locale, note: note, warnings: warnings))
  end
end
