require "rails_helper"

RSpec.describe Report, type: :model do
  describe "associations" do
    it { should belong_to(:reporter).class_name("User") }
    it { should belong_to(:reportable) }

    it "is polymorphic on reportable" do
      assoc = described_class.reflect_on_association(:reportable)
      expect(assoc.options[:polymorphic]).to be true
    end
  end

  describe "validations" do
    it { should validate_presence_of(:reason) }
  end

  describe "enums" do
    it do
      should define_enum_for(:reason).with_values(
        spam: 0, inappropriate: 1, fraud: 2, wrong_category: 3, prohibited_item: 4, other: 5
      )
    end

    it { should define_enum_for(:status).with_values(pending: 0, reviewed: 1, resolved: 2, dismissed: 3) }
  end

  describe "#not_reporting_own_content" do
    it "is invalid when reporting your own listing" do
      owner   = create(:user)
      listing = create(:listing, user: owner)
      report  = build(:report, reporter: owner, reportable: listing)

      expect(report).not_to be_valid
      expect(report.errors[:base]).to include("cannot report your own listing")
    end

    it "is valid when reporting someone else's listing" do
      listing = create(:listing)
      report  = build(:report, reporter: create(:user), reportable: listing)
      expect(report).to be_valid
    end

    it "is invalid when reporting yourself" do
      user   = create(:user)
      report = build(:report, reporter: user, reportable: user)

      expect(report).not_to be_valid
      expect(report.errors[:base]).to include("cannot report yourself")
    end

    it "is valid when reporting another user" do
      report = build(:report, :against_user, reporter: create(:user))
      expect(report).to be_valid
    end
  end

  describe "defaults" do
    it "defaults status to pending" do
      expect(create(:report).status).to eq("pending")
    end
  end
end
