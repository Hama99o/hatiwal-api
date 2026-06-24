require "rails_helper"

RSpec.describe ListingPolicy do
  subject(:policy) { described_class.new(user, listing) }

  let(:owner)   { create(:user) }
  let(:other)   { create(:user) }
  let(:listing) { create(:listing, :active, user: owner) }

  describe "open actions (any authenticated user)" do
    let(:user) { other }

    it { expect(policy.index?).to be true }
    it { expect(policy.show?).to be true }
    it { expect(policy.similar?).to be true }
    it { expect(policy.sold_by?).to be true }
    it { expect(policy.create?).to be true }
    it { expect(policy.save?).to be true }
  end

  describe "#update? / #destroy?" do
    context "when owner" do
      let(:user) { owner }
      it { expect(policy.update?).to be true }
      it { expect(policy.destroy?).to be true }
    end

    context "when not owner" do
      let(:user) { other }
      it { expect(policy.update?).to be false }
      it { expect(policy.destroy?).to be false }
    end
  end

  describe "#publish?" do
    let(:user) { owner }

    it "is true for the owner of a draft" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(owner, draft).publish?).to be true
    end

    it "is false when not a draft" do
      expect(described_class.new(owner, listing).publish?).to be false
    end

    it "is false for a non-owner" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(other, draft).publish?).to be false
    end
  end

  describe "#reserve?" do
    it "is true for the owner of an active listing" do
      expect(described_class.new(owner, listing).reserve?).to be true
    end

    it "is false when not active" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(owner, draft).reserve?).to be false
    end

    it "is false for a non-owner" do
      expect(described_class.new(other, listing).reserve?).to be false
    end
  end

  describe "#sold?" do
    it "is true for the owner of a reserved listing" do
      reserved = create(:listing, :reserved, user: owner)
      expect(described_class.new(owner, reserved).sold?).to be true
    end

    it "is true for the owner of an active listing (sell directly)" do
      expect(described_class.new(owner, listing).sold?).to be true
    end

    it "is false for a draft (must publish first)" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(owner, draft).sold?).to be false
    end

    it "is false once already sold (terminal — never reopen)" do
      sold = create(:listing, :sold, user: owner)
      expect(described_class.new(owner, sold).sold?).to be false
    end

    it "is false for a non-owner" do
      expect(described_class.new(other, listing).sold?).to be false
    end
  end

  describe "#unpublish?" do
    it "is true for the owner of an active listing" do
      expect(described_class.new(owner, listing).unpublish?).to be true
    end

    it "is false when not active" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(owner, draft).unpublish?).to be false
    end

    it "is false for a non-owner" do
      expect(described_class.new(other, listing).unpublish?).to be false
    end
  end

  describe "#activate?" do
    it "is true for the owner of a reserved listing (undo reserve)" do
      reserved = create(:listing, :reserved, user: owner)
      expect(described_class.new(owner, reserved).activate?).to be true
    end

    it "is false when not reserved" do
      expect(described_class.new(owner, listing).activate?).to be false
    end

    it "is false for a non-owner" do
      reserved = create(:listing, :reserved, user: owner)
      expect(described_class.new(other, reserved).activate?).to be false
    end
  end

  describe "#renew?" do
    it "is true for the owner of an active listing" do
      expect(described_class.new(owner, listing).renew?).to be true
    end

    it "is false when not active" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(owner, draft).renew?).to be false
    end

    it "is false for a non-owner" do
      expect(described_class.new(other, listing).renew?).to be false
    end
  end

  describe "#start_conversation?" do
    it "is true for a non-owner on an active listing" do
      expect(described_class.new(other, listing).start_conversation?).to be true
    end

    # The owner check is intentionally absent from the policy — the service
    # layer (Conversations::StartService) raises a 422 error when the listing
    # owner tries to start a conversation on their own listing.  The policy
    # only gates on listing status (active/inactive).
    it "is true for the owner on an active listing (service layer enforces the 422 guard)" do
      expect(described_class.new(owner, listing).start_conversation?).to be true
    end

    it "is false when the listing is not active" do
      draft = create(:listing, :draft, user: owner)
      expect(described_class.new(other, draft).start_conversation?).to be false
    end
  end

  describe "Scope" do
    it "resolves all listings for a guest (nil user)" do
      create_list(:listing, 3)
      scope = ListingPolicy::Scope.new(nil, Listing).resolve
      expect(scope).to match_array(Listing.all)
    end

    it "resolves all listings when there are no block relationships" do
      create_list(:listing, 3)
      scope = ListingPolicy::Scope.new(other, Listing).resolve
      expect(scope).to match_array(Listing.all)
    end

    it "excludes listings from users the viewer has blocked" do
      blocked_seller  = create(:user)
      allowed_seller  = create(:user)
      hidden_listing  = create(:listing, user: blocked_seller)
      visible_listing = create(:listing, user: allowed_seller)
      create(:block, blocker: other, blocked: blocked_seller)

      scope = ListingPolicy::Scope.new(other, Listing).resolve
      expect(scope).to include(visible_listing)
      expect(scope).not_to include(hidden_listing)
    end

    it "excludes listings from users who have blocked the viewer" do
      blocking_seller = create(:user)
      allowed_seller  = create(:user)
      hidden_listing  = create(:listing, user: blocking_seller)
      visible_listing = create(:listing, user: allowed_seller)
      create(:block, blocker: blocking_seller, blocked: other)

      scope = ListingPolicy::Scope.new(other, Listing).resolve
      expect(scope).to include(visible_listing)
      expect(scope).not_to include(hidden_listing)
    end
  end
end
