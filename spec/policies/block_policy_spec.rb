require "rails_helper"

RSpec.describe BlockPolicy do
  let(:user) { create(:user) }

  describe "#create?" do
    it "lets a user block another user" do
      expect(described_class.new(user, Block.new(blocker: user, blocked: create(:user))).create?).to be true
    end

    it "refuses blocking on someone else's behalf" do
      expect(described_class.new(user, Block.new(blocker: create(:user), blocked: create(:user))).create?).to be false
    end

    # A blocked Support thread would leave the user unable to reach help.
    it "refuses blocking the Support account" do
      expect(described_class.new(user, Block.new(blocker: user, blocked: User.support_account!)).create?).to be false
    end
  end
end
