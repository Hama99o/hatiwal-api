# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 1): expiry must never
# catch a seller by surprise. 7 days and 1 day before a listing expires, its
# seller gets a push that opens the listing (with Renew on it), plus the same
# reminder from Hatiwal Support (SupportNoticeJob), in their own language.
#
# Once per listing per expiry: the `expiry_reminder_*_for` column records the
# `expires_at` a reminder was sent for, and is claimed with a conditional UPDATE
# before anything is sent, so an overlapping run cannot send it twice. A renew
# moves `expires_at`, which re-arms both reminders for the new run.
#
# Hourly (config/recurring.yml), so "1 day before" is at most an hour late.
class ListingExpiryReminderJob < ApplicationJob
  queue_as :default

  def perform
    # The day reminder first: a listing already inside the 1-day window gets
    # only that one (it also marks the week reminder as done).
    Listing::EXPIRY_REMINDERS.keys.reverse_each do |reminder|
      Listing.expiry_reminder_due(reminder).includes(:user, :shop).find_each { |listing| remind(listing, reminder) }
    end
  end

  private

  def remind(listing, reminder)
    return unless claim(listing, reminder)

    user = recipient_for(listing)
    return if user.nil? || user.deleted_at.present? || user.account_blocked?

    push(user, listing, reminder)
    SupportNoticeJob.enqueue(user, :"listing_expires_#{reminder}", listing: listing)
  end

  # Marks the reminder sent for THIS expiry; false if another run got there first
  # or the listing was renewed in between.
  def claim(listing, reminder)
    columns = reminder == :day ? %i[expiry_reminder_day_for expiry_reminder_week_for] : [ :expiry_reminder_week_for ]
    Listing.expiry_reminder_due(reminder)
           .where(id: listing.id, expires_at: listing.expires_at)
           .update_all(columns.index_with { listing.expires_at }) == 1
  end

  # Whoever posted it, while they can still manage it; a shop product whose
  # poster has left the team goes to the shop's owner.
  def recipient_for(listing)
    return listing.user if listing.manageable_by?(listing.user)

    listing.shop&.owner
  end

  def push(user, listing, reminder)
    return if user.push_token.blank?

    locale = user.preferred_language.presence&.to_sym
    locale = I18n.default_locale unless locale && I18n.locale_available?(locale)
    title, body = I18n.with_locale(locale) do
      [ I18n.t("push.listing_expiry.#{reminder}_title"), I18n.t("push.listing_expiry.body", title: listing.title) ]
    end

    result = Notifications::ExpoPushService.deliver(
      token: user.push_token, title: title, body: body,
      # `shopId` (null = Me): the app switches to Seller mode as that identity
      # before opening the listing, exactly as for a selling chat.
      data: { type: "listing_expiry", listingId: listing.id, shopId: listing.shop_id, reminder: reminder.to_s }
    )
    user.update_column(:push_token, nil) if result.error.to_s == "DeviceNotRegistered"
  end
end
