require "rails_helper"

# android-headsup (side branch, owner decision 2026-10-09): Android shows a
# heads-up banner only for an IMPORTANCE_HIGH channel. The app's "default"
# channel has been DEFAULT since 2026-06-15 (no banner ever), and Android never
# raises an existing channel's importance — so new apps create a "messages"
# channel at HIGH, and the API sends chat pushes there ONLY to apps that have
# it. An older app keeps "default": a push to a channel it never created may
# not show at all.
RSpec.describe "Android heads-up channel for chat pushes" do
  let(:token) { "ExponentPushToken[abc123]" }

  describe Notifications::ExpoPushService do
    def capture_payload
      sent = nil
      response = instance_double(Net::HTTPResponse, body: { "data" => { "status" => "ok" } }.to_json)
      allow_any_instance_of(Net::HTTP).to receive(:request) { |_, req| sent = JSON.parse(req.body); response }
      yield
      sent
    end

    it "sends the channel it is given" do
      payload = capture_payload { described_class.deliver(token: token, title: "t", body: "b", channel_id: "messages") }
      expect(payload["channelId"]).to eq("messages")
    end

    it "keeps 'default' when no channel is given (every other push)" do
      payload = capture_payload { described_class.deliver(token: token, title: "t", body: "b") }
      expect(payload["channelId"]).to eq("default")
    end
  end

  describe "User#chat_push_channel" do
    def user_on(platform, version) = build(:user, last_app_platform: platform, last_app_version: version)

    it "an Android app that has the channel (>= the minimum) gets 'messages'" do
      expect(user_on("android", "1.1.6").chat_push_channel).to eq("messages")
      expect(user_on("android", "1.2.0").chat_push_channel).to eq("messages")
    end

    it "an older Android app, an unknown version, or iOS keeps 'default'" do
      expect(user_on("android", "1.1.5").chat_push_channel).to eq("default")
      expect(user_on("android", nil).chat_push_channel).to eq("default")
      expect(user_on("android", "garbage").chat_push_channel).to eq("default")
      expect(user_on("ios", "1.1.6").chat_push_channel).to eq("default")
    end

    it "the minimum can be lowered by ENV (QA builds still say 1.1.5)" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PUSH_MESSAGES_CHANNEL_MIN_VERSION", anything).and_return("1.1.5")
      expect(user_on("android", "1.1.5").chat_push_channel).to eq("messages")
    end
  end

  describe SendMessagePushJob do
    it "a chat push goes to the recipient's channel" do
      seller = create(:user, push_token: token, last_app_platform: "android", last_app_version: "1.1.6")
      buyer = create(:user)
      chat = create(:conversation, listing: create(:listing, :active, user: seller), buyer: buyer)
      msg = create(:message, conversation: chat, user: buyer, kind: :text, body: "Salaam")
      ok = Notifications::ExpoPushService::Result.new(ok: true, error: nil, details: nil)
      expect(Notifications::ExpoPushService).to receive(:deliver).with(hash_including(channel_id: "messages")).and_return(ok)
      described_class.perform_now(msg.id)
    end
  end
end
