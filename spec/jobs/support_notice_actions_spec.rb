require "rails_helper"

# Owner, 2026-10-12: Support notices are TAPPABLE. A notice with a natural
# target carries `messages[].action` {type, label_key, params}; the apps show a
# button that opens it (and switch to the shop when it is a shop's). The body
# still says it all, for older apps.
RSpec.describe SupportNoticeJob, "notice actions", type: :job do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let(:admin) { create(:admin_user) }
  let(:owner) { create(:user, :confirmed, firstname: "Tamana", lastname: "Owner") }
  let(:shop) { create(:shop, owner: owner, name: "Kabul Cosmetics") }

  def person_notice(user) = Conversation.person_support.find_by(buyer_id: user.id).messages.sole
  def shop_notices(s = shop) = Conversation.shop_support.find_by(shop_id: s.id).messages.order(:id).to_a
  def action_of(message) = MessageSerializer.render_as_hash(message)[:action]

  def action(type, label, params) = { "type" => type, "label_key" => "chat.noticeAction.#{label}", "params" => params }

  # Owner bug, 2026-10-08: an old "rejected → Try again" notice kept offering
  # a new application while one was under review. The button carries the
  # subject's CURRENT state each time the thread is read.
  describe "the verification button knows the state NOW" do
    it "a person: rejected → requested (under review) → verified" do
      user = create(:user, :verification_eligible)
      request = create(:verification_request, user: user)
      request.reject!(admin: admin, reason_code: "name_mismatch")
      described_class.perform_now(user.id, "user_verification_rejected")
      notice = person_notice(user)
      expect(action_of(notice)["params"]).to include("subject" => "me", "state" => "rejected")

      again = create(:verification_request, user: user)
      expect(action_of(notice.reload)["params"]["state"]).to eq("requested")
      again.approve!(admin: admin)
      expect(action_of(notice.reload)["params"]["state"]).to eq("verified")
    end

    it "a shop: the same, for the shop's thread" do
      request = create(:shop_verification_request, shop: create(:shop, :verification_eligible, owner: owner))
      request.reject!(admin: admin, reason_code: "photo_not_clear")
      described_class.perform_now(owner.id, "shop_verification_rejected", request.subject_id)
      notice = shop_notices(request.subject).last
      expect(action_of(notice)["params"]).to include("subject" => "shop", "state" => "rejected")
      create(:shop_verification_request, shop: request.subject)
      expect(action_of(notice.reload)["params"]["state"]).to eq("requested")
    end

    it "other buttons are untouched" do
      described_class.perform_now(owner.id, "shop_verified", create(:shop, owner: owner, verified_at: Time.current).id) rescue nil
      expect(MessageSerializer.with_live_state(nil, { "type" => "open_shop", "params" => { "shop_id" => 1 } }))
        .to eq({ "type" => "open_shop", "params" => { "shop_id" => 1 } })
    end
  end

  describe "a person's verification" do
    it "rejected: Try verification again, for me" do
      request = create(:verification_request, user: create(:user, :verification_eligible))
      request.reject!(admin: admin, reason_code: "name_mismatch")
      described_class.perform_now(request.subject_id, "user_verification_rejected")

      expect(action_of(person_notice(request.subject))).to eq(action("open_verification", "tryVerificationAgain", { "subject" => "me", "state" => "rejected" }))
    end

    it "badge removed: the same" do
      request = create(:verification_request, user: create(:user, :verification_eligible))
      request.approve!(admin: admin)
      request.revoke!(admin: admin, reason_code: "policy_violation")
      described_class.perform_now(request.subject_id, "user_badge_revoked")

      expect(action_of(person_notice(request.subject))).to eq(action("open_verification", "tryVerificationAgain", { "subject" => "me", "state" => "revoked" }))
    end

    it "verified: no button (nothing to do)" do
      user = create(:user, :verification_eligible)
      create(:verification_request, user: user).approve!(admin: admin)
      described_class.perform_now(user.id, "user_verified")

      expect(person_notice(user).context).to be_nil
      expect(action_of(person_notice(user))).to be_nil
    end
  end

  describe "a shop's verification (in the shop's thread)" do
    let(:request) { create(:shop_verification_request) }
    let(:vshop) { request.subject }

    it "verified: View shop" do
      request.approve!(admin: admin)
      described_class.perform_now(vshop.owner_id, "shop_verified", vshop.id)

      expect(action_of(shop_notices(vshop).sole)).to eq(action("open_shop", "viewShop", { "shop_id" => vshop.id }))
    end

    it "rejected: Try verification again, for the shop" do
      request.reject!(admin: admin, reason_code: "proof_not_accepted")
      described_class.perform_now(vshop.owner_id, "shop_verification_rejected", vshop.id)

      expect(action_of(shop_notices(vshop).sole))
        .to eq(action("open_verification", "tryVerificationAgain", { "subject" => "shop", "shop_id" => vshop.id, "state" => "rejected" }))
    end

    it "badge removed: the same" do
      request.approve!(admin: admin)
      request.revoke!(admin: admin, reason_code: "policy_violation")
      described_class.perform_now(vshop.owner_id, "shop_badge_removed", vshop.id)

      expect(action_of(shop_notices(vshop).sole))
        .to eq(action("open_verification", "tryVerificationAgain", { "subject" => "shop", "shop_id" => vshop.id, "state" => "revoked" }))
    end
  end

  describe "team events" do
    it "an invitation: Open invitation, with its token" do
      invitee = create(:user, :confirmed, email: "gul@hatiwal.test")
      invite = shop.invite!(by: owner, email: "gul@hatiwal.test")
      perform_enqueued_jobs(only: described_class)

      expect(action_of(person_notice(invitee))).to eq(action("open_invite", "openInvite", { "token" => invite.token }))
    end

    it "joining: View team for the shop's team, View shop for the new member" do
      member = create(:user, :confirmed)
      create(:shop_invite, shop: shop).accept!(member)
      perform_enqueued_jobs(only: described_class)

      expect(action_of(shop_notices.sole)).to eq(action("open_team", "viewTeam", { "shop_id" => shop.id }))
      expect(action_of(person_notice(member))).to eq(action("open_shop", "viewShop", { "shop_id" => shop.id }))
    end

    it "removed from the shop: no button (nothing left to open)" do
      member = create(:user, :confirmed)
      create(:shop_member, shop: shop, user: member, role: :staff)
      shop.shop_members.find_by(user: member).destroy!
      described_class.perform_now(member.id, "shop_member_removed", shop.id, {})

      expect(person_notice(member).context).to be_nil
    end
  end

  describe "listing expiry" do
    let(:seller) { create(:user) }

    it "Renew listing: the listing, and the shop it is sold as" do
      listing = create(:listing, :active, user: seller, expires_at: 6.days.from_now)
      described_class.perform_now(seller.id, "listing_expires_week", nil,
                                  { "listing_id" => listing.id, "expires_at" => listing.expires_at.iso8601(6) })

      expect(action_of(person_notice(seller)))
        .to eq(action("open_listing", "renewListing", { "listing_id" => listing.id, "shop_id" => nil }))
    end
  end

  it "every action is a known type, with a label key the apps translate" do
    described_class::ACTIONS.each_value do |type, label|
      expect(Message::NOTICE_ACTION_TYPES).to include(type)
      expect(label).to match(/\A[a-z][A-Za-z]+\z/)
    end
  end

  describe "who can carry an action", type: :request do
    let(:user) { create(:user, :confirmed) }
    let(:thread) { Conversation.support_thread_for!(user) }

    it "a person's own message never keeps one (only mode survives)" do
      message = thread.messages.create!(user: user, kind: :text, body: "Hi",
                                        context: { "mode" => "buyer", "action" => action("open_shop", "viewShop", { "shop_id" => 1 }) })
      expect(message.context).to eq("mode" => "buyer")
      expect(action_of(message)).to be_nil
    end

    it "Support's message drops an unknown action type" do
      message = thread.messages.create!(user: thread.support_user, kind: :text, body: "Hi",
                                        context: { "action" => { "type" => "open_anything", "params" => {} } })
      expect(message.context).to be_nil
    end

    it "the API sends it to the person, under messages[].action" do
      thread.messages.create!(user: thread.support_user, kind: :text, body: "Your shop is verified.",
                              context: { "action" => action("open_shop", "viewShop", { "shop_id" => shop.id }) })
      get "/api/v1/conversations/#{thread.id}/messages", headers: auth_headers_for(user)

      notice = JSON.parse(response.body)["messages"].sole
      expect(notice["action"]).to eq(action("open_shop", "viewShop", { "shop_id" => shop.id }))
      expect(notice["body"]).to eq("Your shop is verified.")
    end
  end
end
