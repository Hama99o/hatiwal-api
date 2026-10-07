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

  # SHOP-3 team events (owner, 2026-10-07: "the same system as for users"),
  # alongside ShopTeamPushJob. key => what must STILL hold when the job runs:
  # (user, shop, actor, invite). `actor` is the other person named in the text.
  TEAM_NOTICES = {
    # The invited (existing, confirmed) account: the invite is still open.
    shop_invite_received: ->(user, shop, _actor, invite) { invite&.pending? && !invite.expired? && !shop.member?(user) },
    # To the OWNER: the person who joined is still on the team.
    shop_member_joined: ->(user, shop, actor, _invite) { shop.owner_id == user.id && actor && shop.member?(actor) },
    # To the person who joined.
    shop_joined: ->(user, shop, _actor, _invite) { shop.member?(user) },
    shop_member_removed: ->(user, shop, _actor, _invite) { !shop.member?(user) },
    shop_role_changed: ->(user, shop, _actor, _invite) { shop.shop_members.where(user: user).where.not(role: :owner).exists? },
    # Transfer: the new owner, and the old owner (now a manager).
    shop_ownership_received: ->(user, shop, _actor, _invite) { shop.owner_id == user.id },
    shop_ownership_handed_over: ->(user, shop, actor, _invite) { actor && shop.owner_id == actor.id && shop.member?(user) }
  }.freeze

  # `shop:` names the shop a shop notice is about (SHOP-2: an owner may have several).
  # Team notices also pass `actor:` (the other person) and/or `invite:`.
  def self.enqueue(user, key, shop: nil, actor: nil, invite: nil)
    raise ArgumentError, "unknown support notice: #{key}" unless NOTICES.key?(key.to_sym) || TEAM_NOTICES.key?(key.to_sym)
    return unless user&.persisted?

    if TEAM_NOTICES.key?(key.to_sym)
      perform_later(user.id, key.to_s, shop.id, { "actor_id" => actor&.id, "invite_id" => invite&.id }.compact)
    else
      shop ? perform_later(user.id, key.to_s, shop.id) : perform_later(user.id, key.to_s)
    end
  end

  def perform(user_id, key, shop_id = nil, team = {})
    key = key.to_sym
    return perform_team(user_id, key, shop_id, team) if TEAM_NOTICES.key?(key)

    still_true = NOTICES[key]
    return unless still_true

    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    shop = shop_for(user, key, shop_id)
    return unless SHOP_NOTICES.include?(key) ? still_true.call(user, shop) : still_true.call(user)

    deliver(user, notice_text(user, key, shop))
  end

  private

  def perform_team(user_id, key, shop_id, team)
    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    shop = Shop.find_by(id: shop_id)
    return unless shop

    actor = User.find_by(id: team["actor_id"]) if team["actor_id"]
    invite = ShopInvite.find_by(id: team["invite_id"], shop_id: shop.id) if team["invite_id"]
    return unless TEAM_NOTICES[key].call(user, shop, actor, invite)

    deliver(user, team_text(user, key, shop, actor, invite))
  end

  def deliver(user, body)
    thread = Conversation.admin_support_thread_for(user)
    return unless thread

    # A retried job must not post the same notice twice.
    return if thread.messages.where(user: thread.seller, body: body).where("created_at > ?", 1.hour.ago).exists?

    message = thread.messages.create!(user: thread.seller, kind: :text, body: body)
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
  end

  # Same fallback as WelcomeSupportMessageJob#welcome_text.
  # The shop must still be the user's own. A job queued before SHOP-2 has no
  # shop_id: then the owner's first shop, as phase 1 did.
  def shop_for(user, key, shop_id)
    return nil unless SHOP_NOTICES.include?(key)

    shop_id ? user.owned_shops.find_by(id: shop_id) : user.owned_shops.first
  end

  def locale_for(user)
    locale = user.preferred_language.presence&.to_sym
    locale && I18n.locale_available?(locale) ? locale : I18n.default_locale
  end

  # Names as the people see them; the role in the reader's language, read when
  # the job runs (the role may have changed since).
  def team_text(user, key, shop, actor, invite)
    I18n.with_locale(locale_for(user)) do
      role = team_role(key, user, shop, actor, invite)
      I18n.t("support.notices.#{key}", name: user.firstname.presence || user.full_name, shop: shop.name,
                                        role: role ? I18n.t("support.team_roles.#{role}") : "",
                                        inviter: invite&.invited_by&.full_name.to_s, member: actor&.full_name.to_s,
                                        actor: actor&.full_name.to_s, new_owner: actor&.full_name.to_s)
    end
  end

  def team_role(key, user, shop, actor, invite)
    case key
    when :shop_invite_received then invite.role
    when :shop_member_joined then shop.shop_members.find_by(user: actor)&.role
    else shop.shop_members.find_by(user: user)&.role
    end
  end

  def notice_text(user, key, shop)
    locale = locale_for(user)
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
