require "rails_helper"

RSpec.describe ConversationPolicy do
  let(:conversation) { create(:conversation) }
  let(:buyer)        { conversation.buyer }
  let(:seller)       { conversation.seller }
  let(:outsider)     { create(:user) }

  describe "#show? / #read_messages?" do
    it "is true for participants" do
      expect(described_class.new(buyer, conversation).show?).to be true
      expect(described_class.new(seller, conversation).show?).to be true
      expect(described_class.new(buyer, conversation).read_messages?).to be true
      expect(described_class.new(seller, conversation).read_messages?).to be true
    end

    it "is false for non-participants" do
      expect(described_class.new(outsider, conversation).show?).to be false
      expect(described_class.new(outsider, conversation).read_messages?).to be false
    end
  end

  describe "#send_message?" do
    it "is true for a participant on an open conversation" do
      expect(described_class.new(buyer, conversation).send_message?).to be true
    end

    it "is false for a non-participant" do
      expect(described_class.new(outsider, conversation).send_message?).to be false
    end

    it "is false when the conversation is closed" do
      closed = create(:conversation, status: :closed)
      expect(described_class.new(closed.buyer, closed).send_message?).to be false
    end
  end

  describe "Scope" do
    it "resolves only conversations the user participates in" do
      mine_as_buyer = conversation
      mine_as_seller = create(:conversation, listing: create(:listing, user: buyer))
      create(:conversation) # unrelated

      scope = ConversationPolicy::Scope.new(buyer, Conversation).resolve
      expect(scope).to contain_exactly(mine_as_buyer, mine_as_seller)
    end
  end
end
