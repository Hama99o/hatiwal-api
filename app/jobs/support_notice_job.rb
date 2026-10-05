# Ready-written messages from Hatiwal Support ("pre-messages"), sent into the
# user's Support thread in THEIR language when something happens to their
# account. Same delivery as WelcomeSupportMessageJob: the thread comes from the
# gate (Conversation.admin_support_thread_for), then broadcast + push.
#
# Enqueued by the action that causes it (e.g. an admin verifying a user in
# Admin::UsersController#update), never by a model callback:
# docs/SUPPORT_MESSAGING.md forbids seeds and backfills creating support threads.
#
# Add a notice: a key in NOTICES, its text under `support.notices.<key>` in all
# four locales, and the enqueue at the action.
class SupportNoticeJob < ApplicationJob
  queue_as :default

  # key => the condition that must STILL hold when the job runs, so a badge
  # switched on and straight off again sends nothing.
  NOTICES = {
    user_verified: ->(user) { user.verified? },
    # VER-1: the latest decision must still be the one the message is about.
    user_verification_rejected: ->(user) { user.latest_verification_request&.rejected? },
    user_badge_revoked: ->(user) { !user.verified? && user.latest_verification_request&.revoked? },
    # SHOP-1/2: sent to the shop's OWNER, about THE shop concerned (the job's
    # shop_id; see #shop_for).
    shop_verified: ->(_user, shop) { shop&.verified? },
    shop_verification_rejected: ->(_user, shop) { shop&.latest_verification_request&.rejected? },
    shop_badge_removed: ->(_user, shop) { shop && !shop.verified? && shop.latest_verification_request&.revoked? },
    # The owner changed the verified shop's name/address: the badge came off.
    shop_reverify_needed: ->(_user, shop) { shop && !shop.verified? && shop.latest_verification_request&.approved? },
    # UPD-1: "please update" for app builds too old to be blocked (1.1.5 and
    # older). Once per user per target version: AppUpdateNotice.
    app_update_available: ->(_user) { true }
  }.freeze

  SHOP_NOTICES = %i[shop_verified shop_verification_rejected shop_badge_removed shop_reverify_needed].freeze

  # `shop:` names the shop a shop notice is about (SHOP-2: an owner may have several).
  def self.enqueue(user, key, shop: nil)
    raise ArgumentError, "unknown support notice: #{key}" unless NOTICES.key?(key.to_sym)
    return unless user&.persisted?

    shop ? perform_later(user.id, key.to_s, shop.id) : perform_later(user.id, key.to_s)
  end

  def perform(user_id, key, shop_id = nil)
    key = key.to_sym
    still_true = NOTICES[key]
    return unless still_true

    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    shop = shop_for(user, key, shop_id)
    return unless SHOP_NOTICES.include?(key) ? still_true.call(user, shop) : still_true.call(user)

    thread = Conversation.admin_support_thread_for(user)
    return unless thread

    body = notice_text(user, key, shop)
    # A retried job must not post the same notice twice.
    return if thread.messages.where(user: thread.seller, body: body).where("created_at > ?", 1.hour.ago).exists?

    message = thread.messages.create!(user: thread.seller, kind: :text, body: body)
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
  end

  private

  # Same fallback as WelcomeSupportMessageJob#welcome_text.
  # The shop must still be the user's own. A job queued before SHOP-2 has no
  # shop_id: then the owner's first shop, as phase 1 did.
  def shop_for(user, key, shop_id)
    return nil unless SHOP_NOTICES.include?(key)

    shop_id ? user.owned_shops.find_by(id: shop_id) : user.owned_shops.first
  end

  def notice_text(user, key, shop)
    locale = user.preferred_language.presence&.to_sym
    locale = I18n.default_locale unless locale && I18n.locale_available?(locale)
    I18n.with_locale(locale) do
      I18n.t("support.notices.#{key}", name: user.firstname.presence || user.full_name, **notice_params(user, key, locale, shop))
    end
  end

  # Extra interpolations a notice needs, e.g. the verification reason in the
  # person's own language.
  def notice_params(user, key, locale, shop)
    case key
    when :user_verification_rejected, :user_badge_revoked
      { reason: user.latest_verification_request.reason_for(locale) }
    when :shop_verified, :shop_reverify_needed
      { shop: shop.name }
    when :shop_verification_rejected, :shop_badge_removed
      { shop: shop.name, reason: shop.latest_verification_request.reason_for(locale) }
    else
      {}
    end
  end
end
