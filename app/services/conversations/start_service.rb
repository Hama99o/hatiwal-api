class Conversations::StartService
  Error = Class.new(StandardError)

  def initialize(buyer:, listing:, message_body:)
    @buyer        = buyer
    @listing      = listing
    @message_body = message_body
  end

  def call
    return existing_conversation if existing_conversation

    raise Error, "you have blocked this user" if @buyer.blocked?(@listing.user)
    raise Error, "you have been blocked by this user" if @listing.user.blocked?(@buyer)

    raise Error, "listing is not active" unless @listing.active?
    raise Error, "cannot start a conversation on your own listing" if @listing.user_id == @buyer.id
    raise Error, "message cannot be blank" if @message_body.blank?

    ActiveRecord::Base.transaction do
      conversation = Conversation.create!(
        listing: @listing,
        buyer:   @buyer,
        seller:  @listing.user
      )
      conversation.messages.create!(
        user: @buyer,
        body: @message_body,
        kind: :text
      )
      conversation
    end
  end

  private

  def existing_conversation
    @existing_conversation ||= Conversation.find_by(listing: @listing, buyer: @buyer)
  end
end
