require "rails_helper"

RSpec.describe SavedSearchPolicy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:saved_search) { create(:saved_search, user: user) }
  let(:other_saved_search) { create(:saved_search, user: other_user) }

  describe "#index?" do
    it "allows authenticated users" do
      policy = SavedSearchPolicy.new(user, SavedSearch)
      expect(policy.index?).to be_truthy
    end

    it "denies unauthenticated users" do
      policy = SavedSearchPolicy.new(nil, SavedSearch)
      expect(policy.index?).to be_falsy
    end
  end

  describe "#create?" do
    it "allows authenticated users" do
      policy = SavedSearchPolicy.new(user, SavedSearch)
      expect(policy.create?).to be_truthy
    end

    it "denies unauthenticated users" do
      policy = SavedSearchPolicy.new(nil, SavedSearch)
      expect(policy.create?).to be_falsy
    end
  end

  describe "#destroy?" do
    it "allows users to delete their own searches" do
      policy = SavedSearchPolicy.new(user, saved_search)
      expect(policy.destroy?).to be_truthy
    end

    it "prevents users from deleting others' searches" do
      policy = SavedSearchPolicy.new(user, other_saved_search)
      expect(policy.destroy?).to be_falsy
    end

    it "denies unauthenticated users" do
      policy = SavedSearchPolicy.new(nil, saved_search)
      expect(policy.destroy?).to be_falsy
    end
  end
end
