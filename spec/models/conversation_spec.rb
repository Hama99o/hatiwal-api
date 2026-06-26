require "rails_helper"

RSpec.describe Conversation, type: :model do
  describe "associations" do
    it { should belong_to(:listing).optional }
    it { should belong_to(:buyer).class_name("User") }
    it { should belong_to(:seller).class_name("User") }
    it { should have_many(:messages).dependent(:destroy) }
    it { should have_one(:latest_message).class_name("Message") }
  end

  describe "validations" do
    it "prevents duplicate conversations for same listing + buyer" do
      listing  = create(:listing, :active)
      buyer    = create(:user)
      create(:conversation, listing: listing, buyer: buyer, seller: listing.user)
      dup = build(:conversation, listing: listing, buyer: buyer, seller: listing.user)
      expect(dup).not_to be_valid
    end

    it "prevents buyer == seller" do
      user = create(:user)
      listing = create(:listing, :active, user: user)
      conv = build(:conversation, listing: listing, buyer: user, seller: user)
      expect(conv).not_to be_valid
    end
  end

  describe "enums" do
    it { should define_enum_for(:status).with_values(open: 0, closed: 1) }
  end

  describe "scopes" do
    describe ".ordered" do
      it "orders by last_message_at desc" do
        older = create(:conversation, last_message_at: 2.hours.ago)
        newer = create(:conversation, last_message_at: 1.minute.ago)
        expect(Conversation.ordered.first).to eq(newer)
        expect(Conversation.ordered.last).to eq(older)
      end
    end

    describe ".for_user" do
      it "returns conversations where the user is buyer or seller" do
        user = create(:user)
        as_buyer  = create(:conversation, buyer: user, listing: create(:listing))
        as_seller = create(:conversation, listing: create(:listing, user: user))
        create(:conversation) # unrelated

        expect(Conversation.for_user(user.id)).to contain_exactly(as_buyer, as_seller)
      end
    end
  end

  describe "#participant?" do
    it "returns true for buyer and seller" do
      conv = create(:conversation)
      expect(conv.participant?(conv.buyer)).to be true
      expect(conv.participant?(conv.seller)).to be true
    end

    it "returns false for other users" do
      conv = create(:conversation)
      other = create(:user)
      expect(conv.participant?(other)).to be false
    end
  end

  describe "#other_participant" do
    it "returns the seller when asked from the buyer's perspective" do
      conv = create(:conversation)
      expect(conv.other_participant(conv.buyer)).to eq(conv.seller)
    end

    it "returns the buyer when asked from the seller's perspective" do
      conv = create(:conversation)
      expect(conv.other_participant(conv.seller)).to eq(conv.buyer)
    end
  end

  describe "#last_message" do
    it "returns the most recent message via SQL when neither association is loaded" do
      conv = create(:conversation)
      _first_msg = conv.messages.create!(user: conv.buyer, body: "first",  kind: :text)
      second_msg = conv.messages.create!(user: conv.buyer, body: "second", kind: :text)
      expect(conv.last_message).to eq(second_msg)
    end

    it "returns nil when there are no messages" do
      conv = create(:conversation)
      expect(conv.last_message).to be_nil
    end

    it "reads from includes(:latest_message) without firing extra SQL" do
      conv = create(:conversation)
      conv.messages.create!(user: conv.buyer, body: "first",  kind: :text)
      second_msg = conv.messages.create!(user: conv.buyer, body: "second", kind: :text)

      # Reload with the same eager-load the index action uses.
      loaded_conv = Conversation.includes(:latest_message).find(conv.id)

      query_count = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { query_count += 1 },
        "sql.active_record"
      ) do
        result = loaded_conv.last_message
        expect(result).to eq(second_msg)
      end

      expect(query_count).to eq(0),
        "Expected last_message to read from the preloaded latest_message association " \
        "without issuing SQL, but #{query_count} queries were fired"
    end

    it "reads from the in-memory messages collection when includes(:messages) is used" do
      conv = create(:conversation)
      conv.messages.create!(user: conv.buyer, body: "first",  kind: :text)
      second_msg = conv.messages.create!(user: conv.buyer, body: "second", kind: :text)

      loaded_conv = Conversation.includes(:messages).find(conv.id)

      query_count = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { query_count += 1 },
        "sql.active_record"
      ) do
        result = loaded_conv.last_message
        expect(result).to eq(second_msg)
      end

      expect(query_count).to eq(0),
        "Expected last_message to read from the preloaded messages collection " \
        "without issuing SQL, but #{query_count} queries were fired"
    end
  end

  describe "archive scopes" do
    let(:user)  { create(:user) }
    let(:other) { create(:user) }

    it ".not_archived_for returns conversations the user has NOT archived" do
      listing = create(:listing, :active, user: other)
      conv_active   = create(:conversation, buyer: user, listing: listing)
      conv_archived = create(:conversation, buyer: user,
                             listing: create(:listing, :active, user: other),
                             buyer_archived_at: Time.current)

      result = Conversation.for_user(user.id).not_archived_for(user)
      expect(result).to include(conv_active)
      expect(result).not_to include(conv_archived)
    end

    it ".archived_for returns conversations the user HAS archived" do
      listing = create(:listing, :active, user: other)
      conv_active   = create(:conversation, buyer: user, listing: listing)
      conv_archived = create(:conversation, buyer: user,
                             listing: create(:listing, :active, user: other),
                             buyer_archived_at: Time.current)

      result = Conversation.for_user(user.id).archived_for(user)
      expect(result).to include(conv_archived)
      expect(result).not_to include(conv_active)
    end
  end

  describe "#archived_for? / #archived_at_for" do
    let(:conv) { create(:conversation) }

    it "returns false for buyer when not archived" do
      expect(conv.archived_for?(conv.buyer)).to be false
    end

    it "returns true for buyer when buyer_archived_at is set" do
      conv.update!(buyer_archived_at: Time.current)
      expect(conv.archived_for?(conv.buyer)).to be true
    end

    it "returns false for seller when not archived" do
      expect(conv.archived_for?(conv.seller)).to be false
    end

    it "returns true for seller when seller_archived_at is set" do
      conv.update!(seller_archived_at: Time.current)
      expect(conv.archived_for?(conv.seller)).to be true
    end

    it "returns nil for a non-participant" do
      other = create(:user)
      expect(conv.archived_at_for(other)).to be_nil
    end
  end

  describe "#archive_for! / #unarchive_for!" do
    let(:conv) { create(:conversation) }

    it "sets buyer_archived_at for the buyer" do
      conv.archive_for!(conv.buyer)
      expect(conv.reload.buyer_archived_at).to be_present
    end

    it "is idempotent for archive (does not change timestamp on second call)" do
      conv.archive_for!(conv.buyer)
      first_ts = conv.reload.buyer_archived_at
      conv.archive_for!(conv.buyer)
      expect(conv.reload.buyer_archived_at).to eq(first_ts)
    end

    it "sets seller_archived_at for the seller" do
      conv.archive_for!(conv.seller)
      expect(conv.reload.seller_archived_at).to be_present
    end

    it "does NOT set seller_archived_at when the buyer archives" do
      conv.archive_for!(conv.buyer)
      expect(conv.reload.seller_archived_at).to be_nil
    end

    it "clears buyer_archived_at on unarchive" do
      conv.update!(buyer_archived_at: Time.current)
      conv.unarchive_for!(conv.buyer)
      expect(conv.reload.buyer_archived_at).to be_nil
    end

    it "is idempotent for unarchive (no error when already unarchived)" do
      expect { conv.unarchive_for!(conv.buyer) }.not_to raise_error
    end
  end

  describe ".not_deleted_for scope" do
    let(:user)  { create(:user) }
    let(:other) { create(:user) }

    it "returns conversations the user has NOT soft-deleted" do
      listing = create(:listing, :active, user: other)
      conv_live    = create(:conversation, buyer: user, listing: listing)
      conv_deleted = create(:conversation, buyer: user,
                            listing: create(:listing, :active, user: other),
                            buyer_deleted_at: Time.current)

      result = Conversation.for_user(user.id).not_deleted_for(user)
      expect(result).to include(conv_live)
      expect(result).not_to include(conv_deleted)
    end

    it "is independent of the other participant's soft-delete" do
      listing = create(:listing, :active, user: other)
      conv = create(:conversation, buyer: user, listing: listing, seller_deleted_at: Time.current)

      # seller deleted their side, but buyer has not — buyer should still see it
      result = Conversation.for_user(user.id).not_deleted_for(user)
      expect(result).to include(conv)
    end
  end

  describe "#listing_deleted?" do
    it "returns false when listing exists and is not removed" do
      conv = create(:conversation)
      expect(conv.listing_deleted?).to be false
    end

    it "returns true when listing is nil (listing was hard-deleted)" do
      conv = create(:conversation)
      conv.update_column(:listing_id, nil)
      expect(conv.reload.listing_deleted?).to be true
    end

    it "returns true when listing has removed_at set" do
      conv = create(:conversation)
      conv.listing.update_column(:removed_at, Time.current)
      expect(conv.listing_deleted?).to be true
    end
  end

  describe "#delete_for!" do
    let(:conv) { create(:conversation) }

    it "sets buyer_deleted_at when the buyer soft-deletes" do
      conv.delete_for!(conv.buyer)
      expect(conv.reload.buyer_deleted_at).to be_present
    end

    it "does NOT set seller_deleted_at when the buyer deletes" do
      conv.delete_for!(conv.buyer)
      expect(conv.reload.seller_deleted_at).to be_nil
    end

    it "sets seller_deleted_at when the seller soft-deletes" do
      conv.delete_for!(conv.seller)
      expect(conv.reload.seller_deleted_at).to be_present
    end

    it "is idempotent — second call does not change the timestamp" do
      conv.delete_for!(conv.buyer)
      first_ts = conv.reload.buyer_deleted_at
      conv.delete_for!(conv.buyer)
      expect(conv.reload.buyer_deleted_at).to eq(first_ts)
    end

    it "hard-deletes the record when both participants have soft-deleted" do
      conv.delete_for!(conv.buyer)
      expect { conv.delete_for!(conv.seller) }.to change(Conversation, :count).by(-1)
    end

    it "does NOT hard-delete after only one participant deletes" do
      conv # materialize before measuring
      expect { conv.delete_for!(conv.buyer) }.not_to change(Conversation, :count)
    end
  end

  describe "#unread_count_for" do
    let(:conv)   { create(:conversation) }
    let(:buyer)  { conv.buyer }
    let(:seller) { conv.seller }

    it "counts messages with no read_at that were not sent by the given user" do
      conv.messages.create!(user: buyer,  body: "hi",    kind: :text)
      conv.messages.create!(user: seller, body: "hello", kind: :text)

      # Seller has 1 unread message (the one from buyer)
      expect(conv.unread_count_for(seller)).to eq(1)
      # Buyer has 1 unread message (the one from seller)
      expect(conv.unread_count_for(buyer)).to eq(1)
    end

    it "excludes messages that have already been read" do
      msg = conv.messages.create!(user: buyer, body: "read me", kind: :text)
      msg.update_column(:read_at, Time.current)

      expect(conv.unread_count_for(seller)).to eq(0)
    end

    it "returns 0 when all messages were sent by the given user" do
      conv.messages.create!(user: seller, body: "mine", kind: :text)

      expect(conv.unread_count_for(seller)).to eq(0)
    end

    it "uses the in-memory collection when messages are already loaded" do
      conv.messages.create!(user: buyer, body: "msg", kind: :text)
      conv.messages.load # force eager load into memory

      query_count = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { query_count += 1 },
        "sql.active_record"
      ) do
        conv.unread_count_for(seller)
      end

      expect(query_count).to eq(0)
    end

    it "falls back to a SQL query when messages are not preloaded" do
      fresh_conv = Conversation.find(conv.id) # no includes
      fresh_conv.messages.create!(user: buyer, body: "msg", kind: :text)
      # Re-fetch so the messages association is not loaded
      fresh_conv = Conversation.find(conv.id)

      query_count = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { query_count += 1 },
        "sql.active_record"
      ) do
        fresh_conv.unread_count_for(seller)
      end

      expect(query_count).to be >= 1
    end
  end
end
