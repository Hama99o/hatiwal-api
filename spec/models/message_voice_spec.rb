require "rails_helper"

# Voice messages (1.2.1, docs/VOICE_MESSAGES.md).
RSpec.describe Message, "voice messages" do
  include ActiveJob::TestHelper

  let(:conversation) { create(:conversation) }
  let(:sender) { conversation.buyer }

  it "is a kind a client may send" do
    expect(described_class::USER_SENDABLE_KINDS).to include("voice_message")
  end

  it "is valid with the server's m4a, duration and waveform" do
    expect(build(:message, :voice, conversation: conversation, user: sender)).to be_valid
  end

  it "is not a voice message without its audio" do
    msg = build(:message, kind: :voice_message, body: "🎤 0:12", voice_duration_ms: 12_000, conversation: conversation, user: sender)

    expect(msg).not_to be_valid
    expect(msg.errors[:attachment]).to be_present
  end

  it "is not a voice message without its measured duration" do
    msg = build(:message, :voice, voice_duration_ms: nil, conversation: conversation, user: sender)

    expect(msg).not_to be_valid
  end

  it "stores only audio/mp4 as a voice message's file" do
    msg = build(:message, :voice, conversation: conversation, user: sender)
    msg.attachment.attach(io: StringIO.new("%PDF-1.4"), filename: "x.pdf", content_type: "application/pdf", identify: false)

    expect(msg).not_to be_valid
  end

  it "never stores audio on another kind" do
    msg = build(:message, kind: :document, body: "a.m4a", conversation: conversation, user: sender)
    msg.attachment.attach(io: StringIO.new("x"), filename: "a.m4a", content_type: "audio/mp4", identify: false)

    expect(msg).not_to be_valid
  end

  describe "#soft_delete!" do
    it "purges the audio of a voice message" do
      msg = create(:message, :voice, conversation: conversation, user: sender)
      blob_id = msg.attachment.blob.id

      perform_enqueued_jobs { msg.soft_delete! }

      expect(msg.reload).to be_deleted
      expect(ActiveStorage::Blob.exists?(blob_id)).to be false
    end

    it "keeps a photo's file as before (only voice is purged)" do
      msg = create(:message, kind: :image_message, body: "p.jpg", conversation: conversation, user: sender)
      msg.attachment.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "p.jpg")

      perform_enqueued_jobs { msg.soft_delete! }

      expect(msg.reload.attachment).to be_attached
    end
  end

  describe "VoiceMessages.body_for" do
    it "reads the same in every language: 🎤 m:ss" do
      expect(VoiceMessages.body_for(3_019)).to eq("🎤 0:03")
      expect(VoiceMessages.body_for(72_400)).to eq("🎤 1:12")
      expect(VoiceMessages.body_for(120_000)).to eq("🎤 2:00")
    end
  end

  it "goes away with the account (messages are destroyed, their files purged)" do
    msg = create(:message, :voice, conversation: conversation, user: sender)
    blob_id = msg.attachment.blob.id

    perform_enqueued_jobs { sender.destroy! }

    expect(described_class.exists?(msg.id)).to be false
    expect(ActiveStorage::Blob.exists?(blob_id)).to be false
  end
end
