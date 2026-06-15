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

    describe "uniqueness of reportable_id scoped to reporter and reportable_type" do
      it "is invalid when the same reporter submits a second report for the same reportable" do
        reporter = create(:user)
        listing  = create(:listing)
        create(:report, reporter: reporter, reportable: listing)

        duplicate = build(:report, reporter: reporter, reportable: listing)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:reportable_id]).to be_present
      end

      it "is valid when a different reporter reports the same reportable" do
        listing = create(:listing)
        create(:report, reportable: listing)

        second = build(:report, reporter: create(:user), reportable: listing)
        expect(second).to be_valid
      end

      it "is valid when the same reporter reports a different listing" do
        reporter  = create(:user)
        listing_a = create(:listing)
        listing_b = create(:listing)
        create(:report, reporter: reporter, reportable: listing_a)

        second = build(:report, reporter: reporter, reportable: listing_b)
        expect(second).to be_valid
      end
    end

    describe "description length" do
      let(:reporter) { create(:user) }
      let(:listing)  { create(:listing) }

      it "is valid when description is nil" do
        report = build(:report, reporter: reporter, reportable: listing, description: nil)
        expect(report).to be_valid
      end

      it "is valid when description is blank" do
        report = build(:report, reporter: reporter, reportable: listing, description: "")
        expect(report).to be_valid
      end

      it "is valid when description is exactly 1000 characters" do
        report = build(:report, reporter: reporter, reportable: listing, description: "a" * 1000)
        expect(report).to be_valid
      end

      it "is invalid when description exceeds 1000 characters" do
        report = build(:report, reporter: reporter, reportable: listing, description: "a" * 1001)
        expect(report).not_to be_valid
        expect(report.errors[:description]).to include(
          be_a(String).and(include("1000"))
        )
      end
    end
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
