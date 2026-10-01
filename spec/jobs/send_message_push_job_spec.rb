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

  # Regression: there was no ur.yml, so with_locale("ur") raised InvalidLocale.
  it "labels a non-text push in Urdu for an Urdu recipient" do
    seller.update!(preferred_language: "ur")
    msg = create(:message, conversation: conversation, user: buyer, kind: :offer, body: "100|AFN|200")

    expect(Notifications::ExpoPushService).to receive(:deliver).with(
      hash_including(body: "پیشکش بھیجی")
    ).and_return(result)

    described_class.perform_now(msg.id)
  end

  it "every supported language has a push label, so no locale raises" do
    User::SUPPORTED_LANGUAGES.each do |lang|
      expect(I18n.t("push.message.image", locale: lang, raise: true)).to be_present
    end
  end

  # The Support account's stored name is English; the push title is composed
  # here and shown by the OS, so it must be in the RECIPIENT's language.
  it "localizes the title of a Support reply to the recipient" do
    user = create(:user, push_token: "ExponentPushToken[user]", preferred_language: "ps")
    thread = Conversation.support_thread_for!(user)
    reply = create(:message, conversation: thread, user: User.support_account!, kind: :text, body: "Salaam")

    expect(Notifications::ExpoPushService).to receive(:deliver).with(
      hash_including(title: "د هتیوال ملاتړ", body: "Salaam")
    ).and_return(result)

    described_class.perform_now(reply.id)
  end

  # The push title must read exactly like the Support name the mobile app
  # shows in the inbox, or a user sees two spellings of the brand.
  it "spells the Support push title exactly as the mobile app does, per locale" do
    expected = { en: "Hatiwal Support", ps: "د هتیوال ملاتړ", fa: "پشتیبانی هتیوال", ur: "ہتیوال سپورٹ" }
    expected.each { |locale, title| expect(I18n.t("push.support.title", locale: locale)).to eq(title) }
  end

  # A Support reply that can never be delivered must not look like a sent one.
  it "logs a Support reply that can't be pushed because the user has no token" do
    user = create(:user, push_token: nil)
    thread = Conversation.support_thread_for!(user)
    reply = create(:message, conversation: thread, user: User.support_account!, body: "Hello")
    allow(Rails.logger).to receive(:warn)

    expect(Notifications::ExpoPushService).not_to receive(:deliver)
    described_class.perform_now(reply.id)

    expect(Rails.logger).to have_received(:warn).with(/Support reply #{reply.id} not pushed: user #{user.id} has no push token/)
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
