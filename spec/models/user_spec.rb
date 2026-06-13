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
