require "rails_helper"

RSpec.describe Message, type: :model do
  describe "associations" do
    it { should belong_to(:conversation) }
    it { should belong_to(:user) }
  end

  describe "validations" do
    it { should validate_presence_of(:body) }
    it { should validate_length_of(:body).is_at_most(1000) }

    describe "responds_to_must_be_in_same_conversation" do
      let(:conversation)       { create(:conversation) }
      let(:other_conversation) { create(:conversation) }

      it "is valid when responds_to belongs to the same conversation" do
        proposal = create(:message, conversation: conversation, kind: :meetup_proposal)
        reply    = build(:message, conversation: conversation, kind: :meetup_accepted,
                                   responds_to: proposal)
        expect(reply).to be_valid
      end

      it "is invalid when responds_to belongs to a different conversation" do
        foreign_proposal = create(:message, conversation: other_conversation, kind: :meetup_proposal)
        reply = build(:message, conversation: conversation, kind: :meetup_accepted,
                                responds_to_id: foreign_proposal.id)
        expect(reply).not_to be_valid
        expect(reply.errors[:responds_to_id]).not_to be_empty
      end

      it "is invalid when responds_to_id references a non-existent message" do
        reply = build(:message, conversation: conversation, kind: :meetup_accepted,
                                responds_to_id: 0)
        expect(reply).not_to be_valid
        expect(reply.errors[:responds_to_id]).not_to be_empty
      end

      it "skips the check when responds_to_id is nil" do
        msg = build(:message, conversation: conversation, responds_to_id: nil)
        expect(msg).to be_valid
      end
    end
  end

  describe "enums" do
    it {
      should define_enum_for(:kind).with_values(
        text: 0, meetup_proposal: 1, system: 2, offer: 3, document: 4, image_message: 5,
        meetup_accepted: 6, meetup_declined: 7, offer_accepted: 8, offer_declined: 9,
        offer_counter: 10
      )
    }
  end

  describe "attachment" do
    it { should have_one_attached(:attachment) }
  end

  # ── TASK-K071 kind-whitelist tests ───────────────────────────────────────
  describe "USER_SENDABLE_KINDS" do
    it "does not include 'system'" do
      expect(Message::USER_SENDABLE_KINDS).not_to include("system")
    end

    it "includes all expected user-sendable kinds" do
      expected = %w[text meetup_proposal meetup_accepted meetup_declined
                    offer offer_accepted offer_declined document image_message offer_counter]
      expect(Message::USER_SENDABLE_KINDS).to match_array(expected)
    end

    it "includes offer_counter" do
      expect(Message::USER_SENDABLE_KINDS).to include("offer_counter")
    end
  end

  describe "offer_counter kind" do
    let(:conversation) { create(:conversation) }

    it "is valid with kind :offer_counter and a pipe-encoded body" do
      msg = build(:message, conversation: conversation, kind: :offer_counter, body: "8500|AFN|10000")
      expect(msg).to be_valid
    end

    it "can link back to the original offer via responds_to" do
      original_offer = create(:message, conversation: conversation, kind: :offer, body: "8000|AFN|10000")
      counter = build(:message, conversation: conversation, kind: :offer_counter,
                                body: "9000|AFN|10000", responds_to: original_offer)
      expect(counter).to be_valid
    end
  end

  describe "kind_must_not_be_system_when_user_authored" do
    it "is invalid when kind is :system" do
      msg = build(:message, kind: :system)
      expect(msg).not_to be_valid
      expect(msg.errors[:kind]).to be_present
    end

    Message::USER_SENDABLE_KINDS.each do |allowed_kind|
      it "is valid when kind is :#{allowed_kind}" do
        expect(build(:message, kind: allowed_kind.to_sym)).to be_valid
      end
    end
  end
  # ── end TASK-K071 ────────────────────────────────────────────────────────

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
