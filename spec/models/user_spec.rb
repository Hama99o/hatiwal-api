require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { should have_one_attached(:avatar) }
    it { should have_many(:listings).dependent(:destroy) }
    it { should have_many(:saved_listings).dependent(:destroy) }
    it { should have_many(:saved_listing_items).through(:saved_listings).source(:listing) }
    it { should have_many(:buyer_conversations).class_name("Conversation").with_foreign_key(:buyer_id).dependent(:destroy) }
    it { should have_many(:seller_conversations).class_name("Conversation").with_foreign_key(:seller_id).dependent(:destroy) }
    it { should have_many(:messages).dependent(:destroy) }
    it { should have_many(:filed_reports).class_name("Report").with_foreign_key(:reporter_id).dependent(:destroy) }
    it { should have_many(:blocks_as_blocker).class_name("Block").with_foreign_key(:blocker_id).dependent(:destroy) }
    it { should have_many(:blocks_as_blocked).class_name("Block").with_foreign_key(:blocked_id).dependent(:destroy) }
    it { should have_many(:blocked_users).through(:blocks_as_blocker).source(:blocked) }
    it { should have_many(:blocking_users).through(:blocks_as_blocked).source(:blocker) }
  end

  describe "validations" do
    it { should validate_presence_of(:firstname) }
    it { should validate_presence_of(:lastname) }

    it "allows blank preferred_language" do
      expect(build(:user, preferred_language: "")).to be_valid
    end

    it "rejects an unsupported preferred_language" do
      expect(build(:user, preferred_language: "ru")).not_to be_valid
    end

    %w[en ps fa].each do |locale|
      it "accepts preferred_language #{locale}" do
        expect(build(:user, preferred_language: locale)).to be_valid
      end
    end

    it "allows blank preferred_theme" do
      expect(build(:user, preferred_theme: "")).to be_valid
    end

    it "rejects an unsupported preferred_theme" do
      expect(build(:user, preferred_theme: "blue")).not_to be_valid
    end

    %w[light dark system].each do |theme|
      it "accepts preferred_theme #{theme}" do
        expect(build(:user, preferred_theme: theme)).to be_valid
      end
    end

    it "allows blank push_token" do
      expect(build(:user, push_token: "")).to be_valid
    end

    it "allows nil push_token" do
      expect(build(:user, push_token: nil)).to be_valid
    end

    it "accepts a push_token within 200 characters" do
      expect(build(:user, push_token: "ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]")).to be_valid
    end

    it "accepts a push_token of exactly 200 characters" do
      expect(build(:user, push_token: "a" * 200)).to be_valid
    end

    it "rejects a push_token exceeding 200 characters" do
      expect(build(:user, push_token: "a" * 201)).not_to be_valid
    end
  end

  describe "enums" do
    it { should define_enum_for(:status).with_values(active: 0, suspended: 1, banned: 2) }
  end

  describe "#full_name" do
    it "joins firstname and lastname" do
      expect(build(:user, firstname: "Ahmad", lastname: "Shah").full_name).to eq("Ahmad Shah")
    end

    it "strips when a part is missing" do
      expect(build(:user, firstname: "Ahmad", lastname: "").full_name).to eq("Ahmad")
    end
  end

  describe "#conversations" do
    it "returns conversations where the user is buyer or seller" do
      user   = create(:user)
      seller = create(:user)
      as_buyer  = create(:conversation, buyer: user, listing: create(:listing, user: seller))
      as_seller = create(:conversation, seller: user, listing: create(:listing, user: user))
      create(:conversation) # unrelated

      expect(user.conversations).to contain_exactly(as_buyer, as_seller)
    end
  end

  describe "#blocked?" do
    it "returns true when the user has blocked the other user" do
      blocker = create(:user)
      blocked = create(:user)
      create(:block, blocker: blocker, blocked: blocked)
      expect(blocker.blocked?(blocked)).to be true
    end

    it "returns false when no block exists" do
      user_a = create(:user)
      user_b = create(:user)
      expect(user_a.blocked?(user_b)).to be false
    end
  end

  describe "#blocked_by?" do
    it "returns true when the other user has blocked this user" do
      blocker = create(:user)
      target = create(:user)
      create(:block, blocker: blocker, blocked: target)
      expect(target.blocked_by?(blocker)).to be true
    end
  end

  describe "#response_rate_percent" do
    let(:seller) { create(:user) }
    let(:listing) { create(:listing, :active, user: seller) }

    def create_conv_with_reply(buyer:, reply_after_seconds:)
      conv = create(:conversation, listing: listing, buyer: buyer, seller: seller)
      first_buyer_msg = create(:message, conversation: conv, user: buyer,
                                         created_at: conv.created_at + 1.minute)
      if reply_after_seconds
        create(:message, conversation: conv, user: seller,
                         created_at: first_buyer_msg.created_at + reply_after_seconds.seconds)
      end
      conv
    end

    it "returns nil when seller has zero conversations" do
      expect(seller.response_rate_percent).to be_nil
    end

    it "returns nil when seller has fewer than 5 conversations (threshold)" do
      4.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 30.minutes) }
      expect(seller.response_rate_percent).to be_nil
    end

    it "returns nil when all conversations are older than 90 days" do
      5.times do
        buyer = create(:user)
        conv = create(:conversation, listing: listing, buyer: buyer, seller: seller,
                                     created_at: 91.days.ago)
        create(:message, conversation: conv, user: buyer, created_at: 91.days.ago + 1.minute)
        create(:message, conversation: conv, user: seller, created_at: 91.days.ago + 2.minutes)
      end
      expect(seller.response_rate_percent).to be_nil
    end

    it "returns 100 when the seller replied within 24h on all conversations" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 30.minutes) }
      expect(seller.response_rate_percent).to eq(100)
    end

    it "returns 0 when the seller never replied within 24h" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: nil) }
      expect(seller.response_rate_percent).to eq(0)
    end

    it "returns correct percentage for a mixed set" do
      # 4 of 5 replied within 24h → 80 %
      4.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 1.hour) }
      create_conv_with_reply(buyer: create(:user), reply_after_seconds: nil)
      expect(seller.response_rate_percent).to eq(80)
    end

    it "does not count a seller reply that arrives after 24h" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 25.hours) }
      expect(seller.response_rate_percent).to eq(0)
    end
  end

  describe "#response_time_label" do
    let(:seller) { create(:user) }
    let(:listing) { create(:listing, :active, user: seller) }

    def create_conv_with_reply(buyer:, reply_after_seconds:)
      conv = create(:conversation, listing: listing, buyer: buyer, seller: seller)
      first_buyer_msg = create(:message, conversation: conv, user: buyer,
                                         created_at: conv.created_at + 1.minute)
      if reply_after_seconds
        create(:message, conversation: conv, user: seller,
                         created_at: first_buyer_msg.created_at + reply_after_seconds.seconds)
      end
      conv
    end

    it "returns nil when threshold is not met" do
      4.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 10.minutes) }
      expect(seller.response_time_label).to be_nil
    end

    it "returns :within_one_hour when median first-response time is ≤ 1 hour" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 30.minutes) }
      expect(seller.response_time_label).to eq(:within_one_hour)
    end

    it "returns :within_a_day when median first-response time is between 1 hour and 24 hours" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 4.hours) }
      expect(seller.response_time_label).to eq(:within_a_day)
    end

    it "returns :within_a_few_days when median first-response time is > 24 hours" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: 30.hours) }
      expect(seller.response_time_label).to eq(:within_a_few_days)
    end

    it "returns :within_a_few_days when seller never replied" do
      5.times { create_conv_with_reply(buyer: create(:user), reply_after_seconds: nil) }
      expect(seller.response_time_label).to eq(:within_a_few_days)
    end
  end

  describe "response rate memoization" do
    let(:seller) { create(:user) }
    let(:listing) { create(:listing, :active, user: seller) }

    it "issues the window query only once when both attributes are read" do
      5.times do
        buyer = create(:user)
        conv  = create(:conversation, listing: listing, buyer: buyer, seller: seller)
        msg   = create(:message, conversation: conv, user: buyer, created_at: conv.created_at + 1.minute)
        create(:message, conversation: conv, user: seller, created_at: msg.created_at + 30.minutes)
      end

      # Reload to get a fresh object with no memoized state.
      fresh_seller = seller.reload

      query_count = 0
      counter     = ->(*, **) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        fresh_seller.response_rate_percent
        fresh_seller.response_time_label   # must NOT issue another query
      end

      # Expect exactly 1 SELECT on conversations + 1 on messages (via includes),
      # not duplicated for the second attribute.
      expect(query_count).to be <= 2
    end

    it "returns consistent values for rate and label in a single call chain" do
      5.times do
        buyer = create(:user)
        conv  = create(:conversation, listing: listing, buyer: buyer, seller: seller)
        msg   = create(:message, conversation: conv, user: buyer, created_at: conv.created_at + 1.minute)
        create(:message, conversation: conv, user: seller, created_at: msg.created_at + 30.minutes)
      end

      expect(seller.response_rate_percent).to eq(100)
      expect(seller.response_time_label).to eq(:within_one_hour)
    end
  end

  describe ".search_by_name" do
    it "returns all when query is blank" do
      create_list(:user, 3)
      expect(User.search_by_name("")).to match_array(User.all)
    end

    it "matches firstname case-insensitively" do
      target = create(:user, firstname: "Mohammad", lastname: "Karimi")
      create(:user, firstname: "Fatima", lastname: "Ahmadi")
      expect(User.search_by_name("mohammad")).to contain_exactly(target)
    end

    it "matches lastname" do
      target = create(:user, firstname: "Sara", lastname: "Noori")
      create(:user, firstname: "Ali", lastname: "Rahimi")
      expect(User.search_by_name("noori")).to contain_exactly(target)
    end

    it "supports multi-word queries (AND semantics)" do
      target = create(:user, firstname: "Mohammad", lastname: "Karimi")
      create(:user, firstname: "Mohammad", lastname: "Noori")
      expect(User.search_by_name("mohammad karimi")).to contain_exactly(target)
    end
  end
end
