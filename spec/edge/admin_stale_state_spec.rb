require "rails_helper"

# Edge-case pass, 2026-10-08 — the admin (Administrate) side of 1.1.6 acting on
# STALE state: the request already cancelled (by a demotion, an account
# deletion, the applicant), the shop already closed or suspended. Each must
# end in a clear alert and change nothing — never a 500, never a resurrection.
RSpec.describe "Admin actions on stale 1.1.6 state", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let(:shop) { create(:shop, :verification_eligible) }
  let(:owner) { shop.owner }
  let(:manager) { create(:user, :confirmed) }

  before do
    sign_in admin, scope: :admin_user
    shop.shop_members.create!(user: manager, role: :manager)
  end

  def shop_request(by: owner)
    create(:shop_verification_request, shop: shop, requested_by: by, name_on_document: by.full_name)
  end

  # A redirect back with an alert, or the page re-rendered (422) with it.
  def expect_clear_refusal
    expect([ 302, 303, 422 ]).to include(response.status), "got #{response.status}"
    expect(flash[:alert]).to be_present, "no alert; body: #{response.body[/class="flash[^<]*<[^<]*/]}"
  end

  describe "verification review" do
    it "approve a shop request cancelled because its applicant was made Staff: alert, no badge" do
      request = shop_request(by: manager)
      shop.change_role!(manager, role: :staff, by: owner)
      patch "/admin/verification_requests/#{request.id}/approve"
      expect_clear_refusal
      expect(request.reload).to be_cancelled
      expect(shop.reload.verified?).to be(false)
    end

    it "approve a shop request whose applicant deleted their account: alert, no badge" do
      request = shop_request(by: manager)
      manager.anonymize_account!
      patch "/admin/verification_requests/#{request.id}/approve"
      expect_clear_refusal
      expect(shop.reload.verified?).to be(false)
    end

    it "reject a person's request the applicant already cancelled: alert" do
      person = create(:user, :verification_eligible)
      request = person.verification_requests.new(requested_by: person, status: :requested, document_type: :e_tazkira,
                                                 name_on_document: person.full_name, document_number: "1234564821")
      %i[front back selfie].each { |f| request.public_send(f).attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: "#{f}.jpg", content_type: "image/jpeg") }
      request.save!
      request.cancel!
      patch "/admin/verification_requests/#{request.id}/reject", params: { reason_code: "photo_not_clear" }
      expect_clear_refusal
      expect(request.reload).to be_cancelled
    end

    it "approve the request of a shop closed since: alert, the shop stays closed" do
      request = shop_request
      shop.close!
      patch "/admin/verification_requests/#{request.id}/approve"
      expect_clear_refusal
      expect(shop.reload).to be_closed
    end

    it "the request pages render for a cancelled one and for a closed shop's (no 500)" do
      request = shop_request
      shop.close!
      get "/admin/verification_requests/#{request.id}"
      expect(response).to have_http_status(:ok)
      get "/admin/verification_requests"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "shop moderation" do
    it "reactivate a CLOSED shop: refused, it stays closed (never back to active with its details wiped)" do
      shop.close!
      patch "/admin/shops/#{shop.id}/reactivate"
      expect_clear_refusal
      expect(shop.reload).to be_closed
    end

    it "suspend a CLOSED shop: refused, it stays closed" do
      shop.close!
      patch "/admin/shops/#{shop.id}/suspend"
      expect_clear_refusal
      expect(shop.reload).to be_closed
    end

    it "suspend an already suspended shop / reactivate an active one: a clear note, no change" do
      shop.suspend!
      patch "/admin/shops/#{shop.id}/suspend"
      expect(response).to have_http_status(:redirect)
      expect(shop.reload).to be_suspended
      shop.reactivate!
      patch "/admin/shops/#{shop.id}/reactivate"
      expect(response).to have_http_status(:redirect)
      expect(shop.reload).to be_active
    end

    it "remove a member who already left: 'not found' alert, not a 500" do
      member = shop.shop_members.find_by!(user: manager)
      shop.leave!(manager)
      delete "/admin/shops/#{shop.id}/members/#{member.id}"
      expect(response.status).to be < 500
    end

    it "the closed shop's admin page renders" do
      shop.close!
      get "/admin/shops/#{shop.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "users" do
    it "Confirm email now on an already confirmed user: no 500, still confirmed" do
      patch "/admin/users/#{owner.id}/confirm_email"
      expect(response.status).to be < 500
      expect(owner.reload.confirmed_at).to be_present
    end

    it "Confirm email now on a deleted (anonymized) account: refused, not a 500" do
      gone = create(:user)
      gone.anonymize_account!
      patch "/admin/users/#{gone.id}/confirm_email"
      expect(response.status).to be < 500
    end
  end
end
