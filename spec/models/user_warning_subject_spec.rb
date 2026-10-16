require "rails_helper"

# A warning now strikes a user OR a shop (owner, 2026-10-16) — exactly one.
RSpec.describe UserWarning, "subject (user or shop)" do
  let(:user) { create(:user) }
  let(:shop) { create(:shop) }

  it "is valid for a user warning (the existing shape)" do
    expect(build(:user_warning, user: user, shop: nil)).to be_valid
  end

  it "is valid for a shop warning" do
    expect(build(:user_warning, :for_shop, shop: shop)).to be_valid
  end

  it "is invalid with neither a user nor a shop" do
    warning = build(:user_warning, user: nil, shop: nil)
    expect(warning).to be_invalid
    expect(warning.errors[:base]).to include(/exactly one/)
  end

  it "is invalid with both a user and a shop" do
    expect(build(:user_warning, user: user, shop: shop)).to be_invalid
  end

  it "reads its display reason safely with no user (a shop warning)" do
    warning = create(:user_warning, :for_shop, shop: shop)
    expect { warning.display_reason }.not_to raise_error
    expect(warning.display_reason).to be_present
  end

  it "keeps the optional poster and listing links" do
    poster = create(:user)
    listing = create(:listing, :active, user: poster)
    warning = create(:user_warning, :for_shop, shop: shop, posted_by: poster, listing: listing)
    expect([ warning.posted_by, warning.listing ]).to eq([ poster, listing ])
  end
end
