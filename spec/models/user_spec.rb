require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { should have_many(:listings).dependent(:destroy) }
    it { should have_many(:saved_listings).dependent(:destroy) }
    it { should have_many(:saved_listing_items).through(:saved_listings).source(:listing) }
    it { should have_many(:buyer_conversations).class_name("Conversation").with_foreign_key(:buyer_id).dependent(:destroy) }
    it { should have_many(:seller_conversations).class_name("Conversation").with_foreign_key(:seller_id).dependent(:destroy) }
    it { should have_many(:messages).dependent(:destroy) }
    it { should have_many(:filed_reports).class_name("Report").with_foreign_key(:reporter_id).dependent(:destroy) }
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
