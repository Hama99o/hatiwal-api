require "rails_helper"

# Edge pass 1.1.6 (hatiwal-d0, 2026-10-08) — a team member deletes their
# account. That is leaving the shop: the same rules as Shop#leave! must hold
# (the shop keeps their products; a badge they applied for comes off).
RSpec.describe "A shop member deletes their account — edge cases" do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:shop) { create(:shop, :verification_eligible) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :manager) } }
  let(:staff) { create(:user, :confirmed).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }

  it "the shop keeps the products the member posted for it (they pass to the owner, still live)" do
    product = create(:listing, :active, user: staff, shop: shop)
    personal = create(:listing, :active, user: staff)

    staff.anonymize_account!

    expect(product.reload).to have_attributes(user_id: owner.id, shop_id: shop.id, removed_at: nil)
    expect(personal.reload.removed_at).to be_present
    expect(shop.reload.member?(staff)).to be(false)
  end

  it "a badge the member applied for comes off, and the owner is told in the shop's thread" do
    request = create(:shop_verification_request, shop: shop, requested_by: manager, name_on_document: manager.full_name)
    request.approve!(admin: admin)
    expect(shop.reload).to be_verified

    manager.anonymize_account!

    expect(shop.reload).not_to be_verified
    expect(ShopAuditEvent.where(shop: shop, action: "badge_dropped")).to exist
    notice = enqueued_jobs.find { |j| j["job_class"] == SupportNoticeJob.name && j["arguments"].first(2) == [ owner.id, "shop_badge_applicant_left" ] }
    expect(notice).to be_present
  end

  it "a badge the OWNER applied for stays when a manager deletes their account" do
    create(:shop_verification_request, shop: shop).approve!(admin: admin)
    manager.anonymize_account!
    expect(shop.reload).to be_verified
  end

  it "the member's active shop selection and team counter are cleared" do
    staff.update_columns(active_shop_id: shop.id)
    staff.anonymize_account!
    expect(staff.reload).to have_attributes(active_shop_id: nil, shop_memberships_count: 0)
  end
end
