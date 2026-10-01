require "rails_helper"

RSpec.describe ReportPolicy do
  let(:user) { create(:user) }

  describe "#create?" do
    it "is true for any authenticated user" do
      report = build(:report, reporter: user)
      expect(described_class.new(user, report).create?).to be true
    end
  end

  describe "Scope" do
    it "resolves only reports filed by the user" do
      mine   = create(:report, reporter: user)
      create(:report, reporter: create(:user)) # someone else's

      scope = ReportPolicy::Scope.new(user, Report).resolve
      expect(scope).to contain_exactly(mine)
    end
  end

  describe "#create? against the Support account" do
    it "refuses a report whose target is the Support account" do
      reporter = create(:user)
      report = Report.new(reporter: reporter, reportable: User.support_account!, reason: :spam)
      expect(described_class.new(reporter, report).create?).to be false
    end

    it "still allows reporting an ordinary user" do
      reporter = create(:user)
      report = Report.new(reporter: reporter, reportable: create(:user), reason: :spam)
      expect(described_class.new(reporter, report).create?).to be true
    end
  end
end
