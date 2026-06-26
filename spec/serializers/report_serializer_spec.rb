require "rails_helper"

RSpec.describe ReportSerializer, type: :serializer do
  let(:reporter) { create(:user) }
  let(:listing)  { create(:listing) }

  describe ":list view — reportable_label for a Listing" do
    let(:report) { create(:report, reporter: reporter, reportable: listing) }

    subject(:data) { described_class.render_as_hash(report, view: :list) }

    it "exposes id, reason, status, description, created_at" do
      expect(data).to include(:id, :reason, :status, :description, :created_at)
    end

    it "exposes reportable_type as 'Listing'" do
      expect(data[:reportable_type]).to eq("Listing")
    end

    it "exposes reportable_id" do
      expect(data[:reportable_id]).to eq(listing.id)
    end

    it "exposes reportable_label as the listing title" do
      expect(data[:reportable_label]).to eq(listing.title)
    end
  end

  describe ":list view — reportable_label for a User" do
    let(:target_user) { create(:user) }
    let(:report) { create(:report, :against_user, reporter: reporter, reportable: target_user) }

    subject(:data) { described_class.render_as_hash(report, view: :list) }

    it "exposes reportable_type as 'User'" do
      expect(data[:reportable_type]).to eq("User")
    end

    it "exposes reportable_label as the user full name" do
      expect(data[:reportable_label]).to eq(target_user.full_name)
    end
  end

  describe ":list view — graceful degradation when reportable user is deleted" do
    let(:target_user) { create(:user) }
    # Report against a user; when that user is deleted the reportable becomes nil
    # (User model does NOT cascade-destroy these reports).
    let!(:report) { create(:report, :against_user, reporter: reporter, reportable: target_user) }

    before { target_user.destroy! }

    subject(:data) { described_class.render_as_hash(report.reload, view: :list) }

    it "returns '[deleted]' for reportable_label" do
      expect(data[:reportable_label]).to eq("[deleted]")
    end

    it "does not raise" do
      expect { data }.not_to raise_error
    end
  end
end
