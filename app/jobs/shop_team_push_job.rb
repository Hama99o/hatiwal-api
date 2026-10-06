# SHOP-3 — the team's pushes (hatiwal-mobile/docs/SHOPS.md, "Phase 3 — the
# team"), in the recipient's language:
#   shop_invite             to an existing account invited by email; carries the
#                           invite's `token` so the tap opens the Join screen
#                           (only an EMAIL invite pushes, and only its bound,
#                           confirmed account can accept it)
#   shop_member_joined      to the owner, when someone joins
#   shop_membership_changed to a person removed (reason "removed") or whose
#                           shop closed (reason "closed"): the app drops them
#                           back to Me and refetches /me
# Silently no-ops when there is no one to tell; never raises.
class ShopTeamPushJob < ApplicationJob
  queue_as :default

  KINDS = %w[shop_invite shop_member_joined shop_membership_changed].freeze

  def perform(kind, recipient_id, shop_id, actor_id = nil, reason = nil, invite_id = nil)
    return unless KINDS.include?(kind)

    recipient = User.find_by(id: recipient_id)
    shop = Shop.find_by(id: shop_id)
    return if recipient.nil? || shop.nil? || recipient.push_token.blank? || recipient.account_blocked?

    actor = User.find_by(id: actor_id)
    locale = recipient.preferred_language.presence&.to_sym
    locale = I18n.default_locale unless locale && I18n.locale_available?(locale)
    key = kind == "shop_membership_changed" ? "#{kind}_#{reason == 'closed' ? 'closed' : 'removed'}" : kind
    body = I18n.with_locale(locale) { I18n.t("push.shop_team.#{key}", shop: shop.name, name: actor&.firstname.presence || actor&.full_name.to_s) }

    result = Notifications::ExpoPushService.deliver(
      token: recipient.push_token, title: shop.name, body: body,
      data: { type: kind, shopId: shop.id, reason: reason, token: invite_token(kind, invite_id, recipient) }.compact
    )
    recipient.update_column(:push_token, nil) if result.error.to_s == "DeviceNotRegistered"
  end

  private

  # Only for a still-usable EMAIL invite bound to this very account.
  def invite_token(kind, invite_id, recipient)
    return nil unless kind == "shop_invite" && invite_id

    invite = ShopInvite.find_by(id: invite_id)
    return nil unless invite&.email.present? && invite.pending? && !invite.expired? && invite.for_account?(recipient)

    invite.token
  end
end
