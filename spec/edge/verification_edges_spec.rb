require "rails_helper"

# Edge-case pass, 2026-10-08 (owner: "check edge cases"). Shop verification
# under the rules of b86a22c: the owner or a manager applies with their own
# e-Tazkira, and the badge vouches for that applicant.
RSpec.describe "Shop verification — edge cases", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:shop) { create(:shop, :verification_eligible) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed) }
  let(:manager2) { create(:user, :confirmed) }

  before do
    shop.shop_members.create!(user: manager, role: :manager)
    shop.shop_members.create!(user: manager2, role: :manager)
  end

  def pending_by(user)
    create(:shop_verification_request, shop: shop, requested_by: user, name_on_document: user.full_name)
  end

  describe "the applicant stops being a manager while the request is under review" do
    it "made Staff: their pending request is cancelled (it can no longer be approved for them)" do
      request = pending_by(manager)
      shop.change_role!(manager, role: :staff, by: owner)
      expect(request.reload).to be_cancelled
      expect { request.approve!(admin: admin) }.to raise_error(ArgumentError)
      expect(shop.reload.verified?).to be(false)
    end

    it "removed: the same" do
      request = pending_by(manager)
      shop.remove_team_member!(manager, by: owner)
      expect(request.reload).to be_cancelled
    end

    it "leaves: the same, and their ID photos are purged" do
      request = pending_by(manager)
      shop.leave!(manager)
      expect(request.reload).to be_cancelled
      expect(request.files_purged_at).to be_present
    end

    it "another manager leaving does not touch it" do
      request = pending_by(manager)
      shop.leave!(manager2)
      expect(request.reload).to be_requested
    end
  end

  it "the owner cannot transfer the shop while a request is pending" do
    pending_by(manager)
    expect { shop.transfer_ownership!(manager2, by: owner) }
      .to raise_error(ShopInvite::Refused) { |e| expect(e.code).to eq(:verification_pending) }
  end

  it "two managers applying at once: one request, the second is told it is already requested" do
    pending_by(manager)
    expect { pending_by(manager2) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "only the applicant cancels their request; another manager cannot" do
    request = pending_by(manager)
    expect(VerificationRequestPolicy.new(manager2, request).destroy?).to be(false)
    expect(VerificationRequestPolicy.new(manager, request).destroy?).to be(true)
  end

  it "the applicant deletes their account: their shop request is cancelled and their ID is forgotten" do
    request = pending_by(manager)
    manager.anonymize_account!
    request.reload
    expect(request).to be_cancelled
    expect([ request.name_on_document, request.document_number, request.document_last4 ]).to eq([ nil, nil, nil ])
    expect(request.files_purged_at).to be_present
  end

  it "a DECIDED shop request of an applicant who deletes their account keeps the decision but forgets the ID" do
    request = pending_by(manager)
    request.approve!(admin: admin)
    manager.anonymize_account!
    request.reload
    expect(request).to be_approved
    expect([ request.name_on_document, request.document_number ]).to eq([ nil, nil ])
  end

  it "the admin cannot approve after the shop was closed (the request was cancelled with it)" do
    request = pending_by(owner)
    shop.close!
    expect(request.reload).to be_cancelled
    expect { request.approve!(admin: admin) }.to raise_error(ArgumentError)
  end
end
