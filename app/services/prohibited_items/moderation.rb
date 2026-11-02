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
      flag.listing? ? take_down_listing!(warn) : take_down_shop!(warn)
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

  def warn_reason
    "Prohibited item (#{category.humanize.downcase}): #{flag.flaggable_label} (flag ##{flag.id})"
  end

  # A listing in a SHOP strikes BOTH the poster (personal account) AND the shop
  # (owner, 2026-10-16). A personal listing strikes only the poster, as before.
  # Back to drafts while live; a sold listing (not live, not a draft) is
  # soft-removed instead. One decision = at most one strike each (the flag lock
  # in #decide! makes take_down! run once).
  def take_down_listing!(warn)
    listing = flag.flaggable
    poster = listing.user
    user_count = strike_poster!(poster, listing) if warn && poster
    shop_count = strike_shop!(listing.shop, poster: poster, listing: listing) if warn && listing.shop

    if listing.live?
      listing.move_to_draft_for_moderation!
    elsif !listing.draft?
      listing.take_down!(reason: "Prohibited item: #{category.humanize.downcase}")
    end

    # The poster hears about their account strike in their OWN Support thread; the
    # shop OWNER hears, in the shop thread, who posted it and the shop's strike count.
    SupportNoticeJob.enqueue_prohibited(listing, :listing_prohibited_removed, category: category, note: note, warnings: user_count)
    return unless listing.shop

    SupportNoticeJob.enqueue_prohibited_shop_owner(listing, category: category, note: note,
                                                           warnings: shop_count, poster: poster)
  end

  # Shops are taken down the way an admin already suspends one (Shop#suspend!:
  # hidden from search, the team sells as themselves, the owner is told in the
  # shop's Support thread). A warning strikes the SHOP (owner, 2026-10-16: the
  # business answers, not the owner's personal account). The reason carries the
  # category and the link.
  def take_down_shop!(warn)
    shop = flag.flaggable
    raise Refused, "#{shop.name} is closed by its owner: there is nothing to take down." if shop.closed?

    shop_count = strike_shop!(shop, poster: nil, listing: nil) if warn
    return if shop.suspended?

    locale = SupportNoticeJob.prohibited_locale(shop.owner)
    shop.suspend!(reason: SupportNoticeJob.prohibited_shop_reason(category, locale: locale, note: note, warnings: shop_count))
  end

  # Strike the poster's personal account; returns their active count. User#issue_warning!
  # is left intact (no new args) — the listing link is set on the returned warning.
  def strike_poster!(poster, listing)
    warning = poster.issue_warning!(admin_user: admin, category: :prohibited_item, reason: warn_reason)
    warning.update!(listing: listing) if listing
    poster.active_warnings_count
  end

  # Strike the shop (3 active → Shop#suspend! fires inside issue_warning!);
  # returns the shop's active count.
  def strike_shop!(shop, poster:, listing:)
    return nil if shop.closed?

    shop.issue_warning!(admin_user: admin, category: :prohibited_item, reason: warn_reason,
                        posted_by: poster, listing: listing)
    shop.active_warnings_count
  end
end
