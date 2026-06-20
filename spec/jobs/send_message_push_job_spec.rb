require "rails_helper"

RSpec.describe SendMessagePushJob, type: :job do
  # conversation.seller is forced to listing.user by the factory, so the seller
  # owns the listing; the buyer initiates. A buyer message must push to seller.
  let(:seller) { create(:user, push_token: "ExponentPushToken[seller]", preferred_language: "en") }
  let(:buyer)  { create(:user, push_token: "ExponentPushToken[buyer]") }
  let(:listing) { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

  def result(error: nil)
    Notifications::ExpoPushService::Result.new(ok: error.nil?, error: error, details: nil)
  end

  it "no-ops for a missing message id" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  it "delivers to the other participant with the sender's name and text body" do
    msg = create(:message, conversation: conversation, user: buyer, kind: :text, body: "Salaam, available?")

    expect(Notifications::ExpoPushService).to receive(:deliver).with(
      hash_including(
        token: seller.push_token,
        title: buyer.full_name,
        body: "Salaam, available?",
        data: hash_including(type: "message", conversationId: conversation.id, messageId: msg.id)
      )
    ).and_return(result)

    described_class.perform_now(msg.id)
  end

  it "shows a localized label for a non-text (offer) message in the recipient's language" do
    seller.update!(preferred_language: "fa")
    msg = create(:message, conversation: conversation, user: buyer, kind: :offer, body: "100|AFN|200")

    expect(Notifications::ExpoPushService).to receive(:deliver).with(
      hash_including(body: I18n.t("push.message.offer", locale: :fa))
    ).and_return(result)

    described_class.perform_now(msg.id)
  end

  it "skips when the recipient has no push token" do
    seller.update!(push_token: nil)
    msg = create(:message, conversation: conversation, user: buyer, kind: :text, body: "hi")

    expect(Notifications::ExpoPushService).not_to receive(:deliver)
    described_class.perform_now(msg.id)
  end

  it "skips when the recipient's account is blocked (suspended/banned)" do
    seller.update!(status: :banned)
    msg = create(:message, conversation: conversation, user: buyer, kind: :text, body: "hi")

    expect(Notifications::ExpoPushService).not_to receive(:deliver)
    described_class.perform_now(msg.id)
  end

  it "skips when either user has blocked the other" do
    create(:block, blocker: seller, blocked: buyer)
    msg = create(:message, conversation: conversation, user: buyer, kind: :text, body: "hi")

    expect(Notifications::ExpoPushService).not_to receive(:deliver)
    described_class.perform_now(msg.id)
  end

  it "skips server-authored system messages (no real participant sender)" do
    system_user = create(:user)
    # A system message is authored by a non-participant system user.
    msg = build(:message, conversation: conversation, user: system_user, kind: :text, body: "joined")
    msg.save!(validate: false)

    expect(Notifications::ExpoPushService).not_to receive(:deliver)
    described_class.perform_now(msg.id)
  end

  it "clears the recipient's stale token when Expo reports DeviceNotRegistered" do
    msg = create(:message, conversation: conversation, user: buyer, kind: :text, body: "hi")
    allow(Notifications::ExpoPushService).to receive(:deliver).and_return(result(error: "DeviceNotRegistered"))

    described_class.perform_now(msg.id)

    expect(seller.reload.push_token).to be_nil
  end
end
