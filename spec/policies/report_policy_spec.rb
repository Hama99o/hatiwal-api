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
end
