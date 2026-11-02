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
    # UPD-1: "please update" for app builds too old to be blocked (1.1.5 and
    # older). Once per user per target version: AppUpdateNotice.
    app_update_available: ->(_user) { true }
  }.freeze

  # Listing expiry reminders (ListingExpiryReminderJob, owner 2026-10-12): to
  # whoever can renew the listing. Sent only while the listing is still live,
  # still theirs, and still on the SAME expiry the reminder was for (a renew
  # in between makes it moot). The push comes from ListingExpiryReminderJob
  # (it opens the listing with Renew), so this one does not push. A shop's
  # listing reminds in the shop's own thread.
  LISTING_NOTICES = %i[listing_expires_week listing_expires_day].freeze

  # Prohibited items (owner, 2026-10-13): to the listing's seller, about THAT
  # listing, in their language (en / ps / fa; anything else reads English),
  # with the reason for its category and the link to the public list. A shop's
  # listing is told in the shop's own thread. Sent whatever the listing's state
  # is by then: it is a record of what Hatiwal did.
  PROHIBITED_NOTICES = %i[listing_prohibited_removed listing_prohibited_auto_drafted listing_prohibited_shop_owner].freeze
  PROHIBITED_LOCALES = %w[en ps fa].freeze
  PROHIBITED_PAGE = "https://hatiwal.com/%<locale>s/prohibited-items".freeze

  SHOP_NOTICES = %i[shop_verified shop_verification_rejected shop_badge_removed].freeze

  # Owner, 2026-10-12: Support is per identity. These are about THE SHOP, so they
  # go to the shop's own Support thread (its whole team reads it); every other
  # notice is about the person and goes to their own thread.
  SHOP_THREAD_NOTICES = (SHOP_NOTICES + %i[shop_member_joined shop_badge_applicant_left shop_suspended shop_reactivated]).freeze

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
    shop_ownership_handed_over: ->(user, shop, actor, _invite) { actor && shop.owner_id == actor.id && shop.member?(user) },
    # To the OWNER, in the shop's thread: the badge came off because the member
    # who applied for it is no longer the owner or a manager (owner, 2026-10-08).
    shop_badge_applicant_left: ->(user, shop, _actor, _invite) { shop.owner_id == user.id && !shop.verified? },
    # To the OWNER, in the shop's thread: an admin suspended / reactivated the
    # shop (owner gap, 2026-10-08), with the admin's reason when given. Still
    # true when the job runs, or nothing is said (a suspension undone at once).
    shop_suspended: ->(user, shop, _actor, _invite) { shop.owner_id == user.id && shop.suspended? },
    shop_reactivated: ->(user, shop, _actor, _invite) { shop.owner_id == user.id && shop.active? }
  }.freeze

  # Their pushes go to the owner AND the managers (Shop#notify_moderation!),
  # not to the whole thread, so the notice itself does not push.
  STATUS_NOTICES = %i[shop_suspended shop_reactivated].freeze

  # Owner, 2026-10-12: a notice with a natural target gets a button
  # (messages[].action) that opens it; the apps pick the identity (Seller mode
  # + the shop) and say so when the target is gone. key => [type, label]; the
  # params come from the notice's own records (#action_for). No entry = no
  # button (nothing left to open, e.g. removed from a shop).
  ACTIONS = {
    user_verification_rejected: %w[open_verification tryVerificationAgain],
    user_badge_revoked: %w[open_verification tryVerificationAgain],
    shop_verified: %w[open_shop viewShop],
    shop_verification_rejected: %w[open_verification tryVerificationAgain],
    shop_badge_removed: %w[open_verification tryVerificationAgain],
    shop_invite_received: %w[open_invite openInvite],
    shop_member_joined: %w[open_team viewTeam],
    shop_joined: %w[open_shop viewShop],
    shop_role_changed: %w[open_shop viewShop],
    shop_ownership_received: %w[open_team viewTeam],
    shop_ownership_handed_over: %w[open_shop viewShop],
    shop_badge_applicant_left: %w[open_verification verifyAgain],
    shop_reactivated: %w[open_shop viewShop],
    listing_expires_week: %w[open_listing renewListing],
    listing_expires_day: %w[open_listing renewListing]
  }.freeze

  # `shop:` names the shop a shop notice is about (SHOP-2: an owner may have several).
  # Team notices also pass `actor:` (the other person) and/or `invite:`.
  def self.enqueue(user, key, shop: nil, actor: nil, invite: nil, listing: nil, reason: nil)
    unless NOTICES.key?(key.to_sym) || TEAM_NOTICES.key?(key.to_sym) || LISTING_NOTICES.include?(key.to_sym)
      raise ArgumentError, "unknown support notice: #{key}"
    end
    return unless user&.persisted?

    if LISTING_NOTICES.include?(key.to_sym)
      perform_later(user.id, key.to_s, listing.shop_id, { "listing_id" => listing.id, "expires_at" => listing.expires_at&.iso8601(6) })
    elsif TEAM_NOTICES.key?(key.to_sym)
      perform_later(user.id, key.to_s, shop.id, { "actor_id" => actor&.id, "invite_id" => invite&.id, "reason" => reason.presence }.compact)
    else
      shop ? perform_later(user.id, key.to_s, shop.id) : perform_later(user.id, key.to_s)
    end
  end

  # Prohibited items: `category` (ProhibitedTerm::CATEGORIES key) says why,
  # `note` is the admin's optional words, `warnings` the seller's active
  # warning count when a warning came with it.
  def self.enqueue_prohibited(listing, key, category: nil, note: nil, warnings: nil)
    raise ArgumentError, "unknown support notice: #{key}" unless PROHIBITED_NOTICES.include?(key.to_sym)
    return unless listing&.user&.persisted?

    perform_later(listing.user_id, key.to_s, listing.shop_id,
                  { "listing_id" => listing.id, "category" => category&.to_s, "note" => note.presence, "warnings" => warnings }.compact)
  end

  # The shop OWNER's message when a team member's listing is taken down (owner,
  # 2026-10-16): it names the poster and carries the SHOP's strike count. Posted
  # in the shop's Support thread (the owner's seat), separate from the poster's
  # own account-strike message.
  def self.enqueue_prohibited_shop_owner(listing, category: nil, note: nil, warnings: nil, poster: nil)
    return unless listing&.shop&.owner&.persisted?

    perform_later(listing.shop.owner_id, "listing_prohibited_shop_owner", listing.shop_id,
                  { "listing_id" => listing.id, "category" => category&.to_s, "note" => note.presence,
                    "warnings" => warnings, "poster" => poster&.full_name }.compact)
  end

  # The Support thread language for prohibited-item messages: en / ps / fa,
  # English for anything else (Urdu is hidden, owner 2026-10-05).
  def self.prohibited_locale(user)
    PROHIBITED_LOCALES.include?(user.preferred_language.to_s) ? user.preferred_language.to_sym : :en
  end

  def self.prohibited_page(locale)
    format(PROHIBITED_PAGE, locale: locale)
  end

  # "<why> (<link>)" plus the note / warning, in `locale`: the reason a shop is
  # suspended for (Shop#suspend! puts it in its own notice).
  def self.prohibited_shop_reason(category, locale:, note: nil, warnings: nil)
    I18n.with_locale(locale) do
      parts = [ "#{I18n.t("support.prohibited.reasons.#{category}")} (#{prohibited_page(locale)})" ]
      parts << I18n.t("support.prohibited.shop_warning", count: warnings, limit: User::WARNING_BLOCK_THRESHOLD) if warnings
      parts << I18n.t("support.prohibited.shop_note", note: note) if note.present?
      parts.join("; ")
    end
  end

  def perform(user_id, key, shop_id = nil, team = {})
    key = key.to_sym
    return perform_prohibited(user_id, key, team) if PROHIBITED_NOTICES.include?(key)
    return perform_listing(user_id, key, team) if LISTING_NOTICES.include?(key)
    return perform_team(user_id, key, shop_id, team) if TEAM_NOTICES.key?(key)

    still_true = NOTICES[key]
    return unless still_true

    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    shop = shop_for(user, key, shop_id)
    return unless SHOP_NOTICES.include?(key) ? still_true.call(user, shop) : still_true.call(user)

    deliver(user, notice_text(user, key, shop), shop: (shop if SHOP_THREAD_NOTICES.include?(key)),
                                                action: action_for(key, shop: shop))
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

    deliver(user, team_text(user, key, shop, actor, invite, team["reason"]), shop: (shop if SHOP_THREAD_NOTICES.include?(key)),
                                                                              push: !STATUS_NOTICES.include?(key),
                                                                              action: action_for(key, shop: shop, invite: invite))
  end

  def perform_listing(user_id, key, data)
    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    listing = Listing.find_by(id: data["listing_id"])
    return unless listing&.live? && listing.removed_at.nil? && listing.manageable_by?(user)
    return unless listing.expires_at&.future? && data["expires_at"].present? &&
                  listing.expires_at.to_i == Time.zone.parse(data["expires_at"]).to_i

    text = I18n.with_locale(locale_for(user)) do
      I18n.t("support.notices.#{key}", name: user.firstname.presence || user.full_name, title: listing.title)
    end
    deliver(user, text, shop: (listing.shop if listing.shop_id), push: false, action: action_for(key, listing: listing))
  end

  def perform_prohibited(user_id, key, data)
    user = User.find_by(id: user_id)
    return if user.nil? || user.support_account? || user.deleted_at.present?

    listing = Listing.find_by(id: data["listing_id"])
    return unless listing

    # The poster's account-strike message is personal; the shop-owner message and
    # the auto-draft notice go to the shop's thread (where the team/owner read).
    thread_shop = key == :listing_prohibited_removed ? nil : listing.shop
    deliver(user, prohibited_text(user, key, listing, data), shop: thread_shop)
  end

  def prohibited_text(user, key, listing, data)
    locale = self.class.prohibited_locale(user)
    I18n.with_locale(locale) do
      category = data["category"].presence_in(ProhibitedTerm::CATEGORIES.keys.map(&:to_s)) || "other"
      shop_owner = key.to_s == "listing_prohibited_shop_owner"
      warning = warning_line(data["warnings"], shop: shop_owner)
      note = data["note"].present? ? I18n.t("support.prohibited.note", note: data["note"]) : ""
      I18n.t("support.notices.#{key}", name: user.firstname.presence || user.full_name, title: listing.title,
                                       poster: data["poster"].to_s,
                                       reason: I18n.t("support.prohibited.reasons.#{category}"),
                                       warning: warning, note: note, link: self.class.prohibited_page(locale))
    end
  end

  # The strike line for a message: a shop strike counts to the shop threshold, a
  # personal strike to the user one. Empty when no warning came with the take-down.
  def warning_line(count, shop:)
    return "" unless count

    key = shop ? "support.prohibited.shop_strike" : "support.prohibited.warning"
    limit = shop ? Shop::SHOP_WARNING_BLOCK_THRESHOLD : User::WARNING_BLOCK_THRESHOLD
    I18n.t(key, count: count, limit: limit)
  end

  # Into the shop's thread when `shop` is given, else the person's own; both
  # through the gate, written by the Support account. `push: false` when the
  # caller sends its own push (e.g. a listing-expiry reminder). `action`: the
  # notice's button (#action_for), kept in the message's context.
  def deliver(user, body, shop: nil, push: true, action: nil)
    thread = shop ? Conversation.admin_shop_support_thread_for(shop) : Conversation.admin_support_thread_for(user)
    return unless thread

    author = thread.support_user
    # A retried job must not post the same notice twice.
    return if thread.messages.where(user: author, body: body).where("created_at > ?", 1.hour.ago).exists?

    message = thread.messages.create!(user: author, kind: :text, body: body, context: action && { "action" => action })
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id) if push
  end

  # The button of notice `key`, or nil. A shop target names the shop; an
  # invite, its token (the app opens the invite screen with it); a listing,
  # its id; a person's verification, `subject: "me"`.
  def action_for(key, shop: nil, invite: nil, listing: nil)
    type, label = ACTIONS[key]
    return nil unless type

    params =
      case type
      when "open_invite" then invite && { "token" => invite.token }
      when "open_listing" then listing && { "listing_id" => listing.id, "shop_id" => listing.shop_id }
      when "open_verification" then shop ? { "subject" => "shop", "shop_id" => shop.id } : { "subject" => "me" }
      else shop && { "shop_id" => shop.id }
      end
    params && { "type" => type, "label_key" => "chat.noticeAction.#{label}", "params" => params }
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
  def team_text(user, key, shop, actor, invite, reason = nil)
    I18n.with_locale(locale_for(user)) do
      role = team_role(key, user, shop, actor, invite)
      # A suspension with the admin's reason has its own wording.
      text_key = key == :shop_suspended && reason.present? ? :shop_suspended_reason : key
      I18n.t("support.notices.#{text_key}", name: user.firstname.presence || user.full_name, shop: shop.name, reason: reason.to_s,
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
    when :shop_verified
      { shop: shop.name }
    when :shop_verification_rejected, :shop_badge_removed
      { shop: shop.name, reason: shop.latest_verification_request.reason_for(locale) }
    else
      {}
    end
  end
end
