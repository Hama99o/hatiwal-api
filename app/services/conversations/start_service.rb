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
    return existing_conversation if existing_conversation

    raise Error.new("you have blocked this user", code: :blocked) if @buyer.blocked?(@listing.user)
    raise Error.new("you have been blocked by this user", code: :blocked_by) if @listing.user.blocked?(@buyer)

    # SF-B1 — `live?`, not `active?`: a reserved listing is still on the market
    # (it is back in the feed and in search), so refusing the first message on it
    # would make the feed advertise a listing the buyer cannot reach.
    raise Error, "listing is not available" unless @listing.live?
    raise Error, "cannot start a conversation on your own listing" if @listing.user_id == @buyer.id
    raise Error, "message cannot be blank" if @message_body.blank?

    message = nil
    conversation = ActiveRecord::Base.transaction do
      created = Conversation.create!(
        listing: @listing,
        buyer:   @buyer,
        seller:  @listing.user
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

  def existing_conversation
    @existing_conversation ||= Conversation.find_by(listing: @listing, buyer: @buyer)
  end
end
