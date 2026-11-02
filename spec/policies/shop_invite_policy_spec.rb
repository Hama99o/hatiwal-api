require "rails_helper"

RSpec.describe ShopInvitePolicy do
  let(:user) { create(:user, :confirmed, email: "mine@hatiwal.test") }

  describe "#index?" do
    it "allows a signed-in user" do
      expect(described_class.new(user, ShopInvite).index?).to be(true)
    end

    it "denies a guest" do
      expect(described_class.new(nil, ShopInvite).index?).to be(false)
    end
  end

  describe "Scope" do
    it "returns only the live invitations addressed to the user's confirmed email" do
      mine = create(:shop_invite, email: "mine@hatiwal.test")
      create(:shop_invite, email: "other@hatiwal.test")
      create(:shop_invite)

      expect(described_class::Scope.new(user, ShopInvite).resolve).to contain_exactly(mine)
    end

    it "returns nothing for a guest or an unconfirmed email" do
      create(:shop_invite, email: "mine@hatiwal.test")
      expect(described_class::Scope.new(nil, ShopInvite).resolve).to be_empty
      user.update_columns(confirmed_at: nil)
      expect(described_class::Scope.new(user, ShopInvite).resolve).to be_empty
    end
  end
end
