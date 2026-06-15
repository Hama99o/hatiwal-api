require "rails_helper"

RSpec.describe Conversations::StartService do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:listing) { create(:listing, :active, user: seller) }

  subject(:service) do
    described_class.new(buyer: buyer, listing: listing, message_body: "Still available?")
  end

  it "creates a conversation" do
    expect { service.call }.to change(Conversation, :count).by(1)
  end

  it "creates the first message" do
    expect { service.call }.to change(Message, :count).by(1)
  end

  it "sets buyer and seller correctly" do
    conv = service.call
    expect(conv.buyer).to eq(buyer)
    expect(conv.seller).to eq(seller)
  end

  it "returns the existing conversation when one already exists" do
    existing = create(:conversation, listing: listing, buyer: buyer, seller: seller)
    result = service.call
    expect(result).to eq(existing)
    expect(Conversation.count).to eq(1)
  end

  it "raises error when listing is not active" do
    draft_listing = create(:listing, :draft, user: seller)
    svc = described_class.new(buyer: buyer, listing: draft_listing, message_body: "hi")
    expect { svc.call }.to raise_error(Conversations::StartService::Error)
  end

  it "raises error when buyer is the seller" do
    svc = described_class.new(buyer: seller, listing: listing, message_body: "hi")
    expect { svc.call }.to raise_error(Conversations::StartService::Error)
  end

  it "raises error when message is blank" do
    svc = described_class.new(buyer: buyer, listing: listing, message_body: "")
    expect { svc.call }.to raise_error(Conversations::StartService::Error)
  end

  describe "block checks" do
    context "when the buyer has blocked the seller" do
      before { create(:block, blocker: buyer, blocked: seller) }

      it "raises Error with an appropriate message" do
        expect { service.call }
          .to raise_error(Conversations::StartService::Error, "you have blocked this user")
      end

      it "creates no Conversation rows" do
        expect { service.call rescue nil }.not_to change(Conversation, :count)
      end

      it "creates no Message rows" do
        expect { service.call rescue nil }.not_to change(Message, :count)
      end
    end

    context "when the buyer has been blocked by the seller" do
      before { create(:block, blocker: seller, blocked: buyer) }

      it "raises Error with an appropriate message" do
        expect { service.call }
          .to raise_error(Conversations::StartService::Error, "you have been blocked by this user")
      end

      it "creates no Conversation rows" do
        expect { service.call rescue nil }.not_to change(Conversation, :count)
      end

      it "creates no Message rows" do
        expect { service.call rescue nil }.not_to change(Message, :count)
      end
    end

    context "when neither party has blocked the other" do
      it "succeeds and creates a conversation" do
        expect { service.call }.to change(Conversation, :count).by(1)
      end
    end

    context "when an existing conversation already exists and one party later blocks the other" do
      let!(:existing) { create(:conversation, listing: listing, buyer: buyer, seller: seller) }

      before { create(:block, blocker: buyer, blocked: seller) }

      it "still returns the existing conversation without creating new Conversation rows" do
        expect { service.call }.not_to change(Conversation, :count)
      end

      it "still returns the existing conversation without creating new Message rows" do
        expect { service.call }.not_to change(Message, :count)
      end

      it "returns a Conversation record" do
        expect(service.call).to be_a(Conversation)
      end
    end
  end
end
