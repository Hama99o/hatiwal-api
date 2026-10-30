require "rails_helper"

# Voice messages (1.2.1): the push says "🎤 Voice message" in the recipient's
# language, never the audio and never the "🎤 0:12" body.
RSpec.describe SendMessagePushJob, "voice messages", type: :job do
  let(:seller) { create(:user, push_token: "ExponentPushToken[seller]", preferred_language: "en") }
  let(:buyer)  { create(:user, push_token: "ExponentPushToken[buyer]") }
  let(:listing) { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }
  let(:ok) { Notifications::ExpoPushService::Result.new(ok: true, error: nil, details: nil) }

  { "en" => "🎤 Voice message", "ps" => "🎤 غږیز پیغام", "fa" => "🎤 پیام صوتی", "ur" => "🎤 صوتی پیغام" }.each do |lang, text|
    it "says #{text} to a #{lang} recipient" do
      seller.update!(preferred_language: lang)
      msg = create(:message, :voice, conversation: conversation, user: buyer)

      expect(Notifications::ExpoPushService).to receive(:deliver).with(hash_including(body: text)).and_return(ok)

      described_class.perform_now(msg.id)
    end
  end

  it "every supported language has the label" do
    User::SUPPORTED_LANGUAGES.each do |lang|
      expect(I18n.t("push.message.voice", locale: lang, raise: true)).to be_present
    end
  end
end
