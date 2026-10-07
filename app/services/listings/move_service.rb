# Owner, 2026-10-12 (hatiwal-mobile docs/OWNER_ITEMS_2026-10-12.md, item 5):
# "Move to shop" — a listing changes who sells it: Me ⇄ a shop, shop ⇄ shop.
#
# Who may move it (docs/SHOPS.md: every member adds/edits/deletes/MOVES the
# shop's products):
#   - out of Me: its poster;
#   - out of a shop: any member, but out to "Me" only its poster or the shop's
#     owner (a staff member does not take the shop's goods home);
#   - into a shop: a member of it, and the shop must be open.
# The actor becomes the listing's poster (`user`), so the listing always
# belongs to someone on the team that now sells it.
#
# What moves and what doesn't:
#   - the listing, its photos, its expiry and its place in the feed: unchanged;
#   - its CHATS do not move. Each was pinned to the identity it started with
#     (conversations.shop_id), and stays there, readable. Every open one gets a
#     system notice "This listing moved to <Shop>" and is closed; the buyer
#     reopens the listing from its new seller to start a new conversation.
#   - a listing with a hold, a sold one, or a removed one cannot move: a hold
#     and a sale belong to the identity they were made with.
class Listings::MoveService
  class Error < StandardError
    attr_reader :code, :status

    def initialize(message = nil, code:, status: :unprocessable_entity)
      super(message)
      @code = code
      @status = status
    end
  end

  NOTICE = "listing_moved".freeze

  # `shop_id`: the target shop's id, or nil/"" for Me.
  def initialize(listing:, actor:, shop_id:)
    @listing = listing
    @actor   = actor
    @shop_id = shop_id.presence&.to_i
  end

  def call
    target = target_shop
    check!(target)

    ActiveRecord::Base.transaction do
      @listing.lock!
      raise Error.new("release the hold before moving this listing", code: :move_has_hold) if held?

      @listing.update!(shop: target, user: @actor)
      tell_and_close_chats(target)
    end
    @listing
  end

  private

  def target_shop
    return nil if @shop_id.nil?

    shop = Shop.find_by(id: @shop_id)
    raise Error.new("you are not on that shop's team", code: :move_not_member, status: :forbidden) unless shop&.member?(@actor)
    raise Error.new("that shop is not open", code: :shop_unavailable) unless shop.active?

    shop
  end

  def check!(target)
    raise Error.new("it is already there", code: :move_same_place) if target&.id == @listing.shop_id
    raise Error.new("a sold or removed listing cannot move", code: :move_not_movable) if @listing.sold? || @listing.removed?
    raise Error.new("release the hold before moving this listing", code: :move_has_hold) if held?
    return unless target.nil? && @listing.shop

    # Out of a shop to Me: the poster, or the shop's owner.
    return if @listing.user_id == @actor.id || @listing.shop.owner_id == @actor.id

    raise Error.new("only its poster or the shop's owner can take it out of the shop", code: :move_forbidden, status: :forbidden)
  end

  def held? = @listing.reserved? || @listing.held_units.positive?

  # Each open chat: a notice in the buyer's language (older apps show it as
  # is; newer ones localize it from `context`), then closed. Broadcast so an
  # open thread shows it at once; no push.
  def tell_and_close_chats(target)
    name = target ? target.name : @actor.full_name
    @listing.conversations.kind_listing.open.find_each do |conversation|
      message = conversation.messages.new(
        kind: :system, user: conversation.seller,
        body: I18n.with_locale(locale_for(conversation.buyer)) { I18n.t("listing_move.notice", name: name) },
        context: { "notice" => NOTICE, "shop_id" => target&.id, "name" => name }
      )
      # Server-written: a :system message is refused from clients by validation.
      message.save!(validate: false)
      conversation.update_column(:status, Conversation.statuses[:closed])
      BroadcastMessageJob.perform_later(message.id)
    end
  end

  def locale_for(user)
    locale = user&.preferred_language.presence&.to_sym
    locale && I18n.locale_available?(locale) ? locale : I18n.default_locale
  end
end
