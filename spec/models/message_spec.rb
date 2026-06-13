require "rails_helper"

RSpec.describe Message, type: :model do
  describe "associations" do
    it { should belong_to(:conversation) }
    it { should belong_to(:user) }
  end

  describe "validations" do
    it { should validate_presence_of(:body) }
    it { should validate_length_of(:body).is_at_most(1000) }
  end

  describe "enums" do
    it { should define_enum_for(:kind).with_values(text: 0, meetup_proposal: 1, system: 2, offer: 3, document: 4, image_message: 5) }
  end

  describe "attachment" do
    it { should have_one_attached(:attachment) }
  end

  describe "scopes" do
    describe ".ordered" do
      it "orders by created_at ascending" do
        conversation = create(:conversation)
        first  = create(:message, conversation: conversation, created_at: 2.hours.ago)
        second = create(:message, conversation: conversation, created_at: 1.hour.ago)
        expect(conversation.messages.ordered.to_a).to eq([ first, second ])
      end
    end
  end

  describe "after_create callback" do
    it "updates the conversation's last_message_at to the message created_at" do
      conversation = create(:conversation)
      message = create(:message, conversation: conversation)
      expect(conversation.reload.last_message_at).to be_within(1.second).of(message.created_at)
    end
  end

  describe "#read?" do
    it "is false when read_at is nil" do
      expect(build(:message, read_at: nil).read?).to be false
    end

    it "is true when read_at is present" do
      expect(build(:message, read_at: Time.current).read?).to be true
    end
  end

  describe "#mark_read!" do
    it "sets read_at when unread" do
      message = create(:message, read_at: nil)
      expect { message.mark_read! }.to change { message.reload.read_at }.from(nil)
    end

    it "does not overwrite an existing read_at" do
      original = 1.day.ago
      message = create(:message, read_at: original)
      message.mark_read!
      expect(message.reload.read_at).to be_within(1.second).of(original)
    end
  end
end
