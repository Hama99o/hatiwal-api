# SHOP-2 — "Message shop" from the shop page: a chat with the shop that has no
# product. Find-or-create, one per buyer and shop (a unique partial index backs
# it up). The seller side is the shop's owner; phase 3 adds the team.
class Conversations::StartShopService
  Error = Class.new(StandardError)
  OwnShop = Class.new(Error)

  attr_reader :created

  def initialize(buyer:, shop:, message_body: nil)
    @buyer = buyer
    @shop = shop
    @message_body = message_body.to_s.strip
  end

  def call
    raise OwnShop, "you cannot message your own shop" if @shop.owner_id == @buyer.id || @shop.member?(@buyer)

    owner = @shop.owner
    raise Error, "you have blocked this user" if @buyer.blocked?(owner)
    raise Error, "you have been blocked by this user" if owner.blocked?(@buyer)

    existing = find_existing
    return existing.tap { add_message(existing) } if existing

    ActiveRecord::Base.transaction do
      conversation = Conversation.create!(shop: @shop, buyer: @buyer, seller: owner)
      add_message(conversation)
      @created = true
      conversation
    end
  rescue ActiveRecord::RecordNotUnique
    # A double tap: the other request created it.
    find_existing.tap { |c| add_message(c) }
  end

  private

  def find_existing = Conversation.find_by(shop: @shop, buyer: @buyer, listing_id: nil)

  def add_message(conversation)
    return if @message_body.blank?

    message = conversation.messages.create!(user: @buyer, body: @message_body, kind: :text)
    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
  end
end
