require "rails_helper"

RSpec.describe ShopPolicy do
  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:stranger) { create(:user) }

  def policy(user, record = shop) = described_class.new(user, record)

  it "shows an active shop to anyone, a suspended one to members only" do
    expect(policy(nil).show?).to be(true)
    shop.suspended!
    expect(policy(nil).show?).to be(false)
    expect(policy(stranger).show?).to be(false)
    expect(policy(owner).show?).to be(true)
  end

  it "lets the owner and a manager edit; only the owner delete" do
    manager = create(:shop_member, shop: shop, role: :manager).user
    staff = create(:shop_member, shop: shop, role: :staff).user
    expect([ policy(owner).update?, policy(manager).update?, policy(staff).update?, policy(stranger).update? ]).to eq([ true, true, false, false ])
    expect([ policy(owner).destroy?, policy(manager).destroy?, policy(staff).destroy? ]).to eq([ true, false, false ])
  end

  it "lets every member move listings, nobody else" do
    staff = create(:shop_member, shop: shop, role: :staff).user
    expect([ policy(owner).move_listings?, policy(staff).move_listings?, policy(stranger).move_listings? ]).to eq([ true, true, false ])
  end

  it "scopes to visible shops plus the user's own" do
    mine = create(:shop, owner: stranger, status: :suspended)
    other_suspended = create(:shop, status: :suspended)
    visible = shop
    expect(described_class::Scope.new(stranger, Shop).resolve).to include(visible, mine)
    expect(described_class::Scope.new(stranger, Shop).resolve).not_to include(other_suspended)
    expect(described_class::Scope.new(nil, Shop).resolve).to contain_exactly(visible)
  end
end
