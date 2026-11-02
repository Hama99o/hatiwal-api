require "rails_helper"

# Owner decision G4 (OWNER_DECISIONS_2026-10-09 #4): an ownership transfer no
# longer always drops the Verified badge. The 2026-10-08 rule holds: the badge
# vouches for its APPLICANT and stays while they are still the owner or a
# manager. A plain transfer leaves the old owner a manager, so it keeps the
# badge; once the applicant becomes Staff (or leaves), it comes off.
RSpec.describe "Ownership transfer and the Verified badge (G4)" do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:shop) { create(:shop, :verification_eligible) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :manager) } }

  before do
    create(:shop_verification_request, shop: shop).approve!(admin: admin) # the OWNER applies
    expect(shop.reload).to be_verified
  end

  it "a plain transfer keeps the badge: its applicant, the old owner, is now a manager" do
    shop.transfer_ownership!(manager, by: owner)

    expect(shop.reload).to have_attributes(owner_id: manager.id)
    expect(shop).to be_verified
    expect(ShopAuditEvent.find_by(shop: shop, action: "transferred").data).to include("badge_dropped" => false)
    expect(ShopAuditEvent.where(shop: shop, action: "badge_dropped")).not_to exist
  end

  it "transfer, then the old owner (the applicant) is made Staff: the badge comes off and the owner is told" do
    shop.transfer_ownership!(manager, by: owner)
    shop.change_role!(owner, role: :staff, by: manager)

    expect(shop.reload).not_to be_verified
    expect(ShopAuditEvent.where(shop: shop, action: "badge_dropped")).to exist
    notice = enqueued_jobs.find { |j| j["job_class"] == SupportNoticeJob.name && j["arguments"].first(2) == [ manager.id, "shop_badge_applicant_left" ] }
    expect(notice).to be_present
  end

  it "transfer, then the old owner (the applicant) leaves: the badge comes off" do
    shop.transfer_ownership!(manager, by: owner)
    shop.leave!(owner)

    expect(shop.reload).not_to be_verified
  end
end
