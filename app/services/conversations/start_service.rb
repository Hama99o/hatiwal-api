class Conversations::StartService
  # `code` (e.g. :blocked / :blocked_by) is the stable token the apps translate;
  # the message stays English prose for older clients.
  class Error < StandardError
    attr_reader :code

    def initialize(message = nil, code: nil)
      super(message)
      @code = code
    end
  end

  def initialize(buyer:, listing:, message_body:)
    @buyer        = buyer
    @listing      = listing
    @message_body = message_body
  end

  def call
    return reopened(existing_conversation) if existing_conversation

    seller = chat_seller
    raise Error.new("you have blocked this user", code: :blocked) if @buyer.blocked?(seller)
    raise Error.new("you have been blocked by this user", code: :blocked_by) if seller.blocked?(@buyer)

    # SF-B1 — `live?`, not `active?`: a reserved listing is still on the market
    # (it is back in the feed and in search), so refusing the first message on it
    # would make the feed advertise a listing the buyer cannot reach.
    raise Error, "listing is not available" unless @listing.live?
    raise Error, "cannot start a conversation on your own listing" if @listing.user_id == @buyer.id
    # SHOP-3: the shop's team doesn't buy from its own shop.
    raise Error.new("you cannot message your own shop", code: :own_shop) if @listing.shop&.member?(@buyer)
    raise Error, "message cannot be blank" if @message_body.blank?

    message = nil
    conversation = ActiveRecord::Base.transaction do
      # SHOP-3: a shop product's chat is with the shop, so its seller is the
      # shop's owner whoever posted it (docs/SHOPS.md, "Phase 3 — the team").
      created = Conversation.create!(
        listing: @listing,
        # PINNED here: the chat belongs to the shop the product is in NOW, and
        # keeps that even if the product moves later (a personal chat stays
        # personal; staff never see it).
        shop_id: @listing.shop_id,
        buyer:   @buyer,
        seller:  chat_seller
      )
      message = created.messages.create!(
        user: @buyer,
        body: @message_body,
        kind: :text
      )
      created
    end
    # The buyer's first message reaches the seller like every other one: live
    # in an open app, and as a push. It used to do neither.
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
    conversation
  end

  private

  # A shop product's chat is with the shop: its seller is the shop's owner.
  def chat_seller = @listing.shop&.owner || @listing.user

  # The chat with the listing's CURRENT seller identity: a listing that moved to
  # another shop left its old chats with the old identity (Listings::MoveService).
  def existing_conversation
    @existing_conversation ||= Conversation.find_by(listing: @listing, buyer: @buyer, shop_id: @listing.shop_id)
  end

  # Moved away and back: the chat that was closed by the move opens again.
  def reopened(conversation)
    conversation.update_column(:status, Conversation.statuses[:open]) if conversation.closed? && @listing.live?
    conversation
  end
end
