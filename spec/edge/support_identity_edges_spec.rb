require "rails_helper"

# Edge pass 1.1.6 (hatiwal-d0, 2026-10-08) — Support per identity: archive and
# resurface, the shop's thread for its whole team, and a leaver losing it.
RSpec.describe "Support per identity — edge cases", type: :request do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let(:owner) { create(:user, preferred_language: "en") }
  let(:shop) { create(:shop, owner: owner) }
  let(:manager) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :manager) } }
  let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:support) { User.support_account! }
  let!(:thread) { Conversation.shop_support_thread_for!(shop) }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user)

  def inbox_ids(user, **params)
    get "/api/v1/conversations", params: params, headers: h(user)
    json["conversations"].pluck("id")
  end

  def archived_ids(user, **params) = inbox_ids(user, archived: true, **params)
  def say(conv, author, body = "Note", **attrs) = conv.messages.create!(user: author, kind: :text, body: body, **attrs)

  describe "archive, then Support writes again" do
    it "a person's thread: a reply from Support brings it back" do
      person = Conversation.support_thread_for!(owner)
      say(person, support)
      put "/api/v1/conversations/#{person.id}/archive", headers: h(owner)
      expect(inbox_ids(owner, role: "buying")).not_to include(person.id)

      say(person, support, "Answer to your question")
      expect(inbox_ids(owner, role: "buying")).to include(person.id)
    end

    it "a shop's thread archived by Staff: a reply from Support brings it back for the whole team" do
      say(thread, support)
      put "/api/v1/conversations/#{thread.id}/archive", headers: h(staff)
      expect(response).to have_http_status(:no_content)
      # The seller side's archive is shared by the team (one inbox).
      expect(inbox_ids(owner, role: "selling", shop_id: shop.id)).to eq([])
      expect(archived_ids(manager, role: "selling", shop_id: shop.id)).to eq([ thread.id ])

      say(thread, support, "Your badge was approved")
      [ owner, manager, staff ].each do |member|
        expect(inbox_ids(member, role: "selling", shop_id: shop.id)).to eq([ thread.id ])
      end
    end

    it "a broadcast is delivered quietly: an archived thread stays archived" do
      person = Conversation.support_thread_for!(owner)
      say(person, support)
      put "/api/v1/conversations/#{person.id}/archive", headers: h(owner)
      say(person, support, "Announcement", broadcast: true)
      expect(inbox_ids(owner, role: "buying")).not_to include(person.id)
    end

    it "a member writing into the archived shop thread brings it back too" do
      say(thread, support)
      put "/api/v1/conversations/#{thread.id}/archive", headers: h(owner)
      post "/api/v1/conversations/#{thread.id}/messages", params: { body: "Still stuck" }, headers: h(staff)
      expect(response).to have_http_status(:created)
      expect(inbox_ids(owner, role: "selling", shop_id: shop.id)).to eq([ thread.id ])
    end

    it "the Support thread can be archived but never deleted, by any member" do
      delete "/api/v1/conversations/#{thread.id}", headers: h(staff)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Conversation.exists?(thread.id)).to be(true)
    end
  end

  describe "a member who leaves, or is removed, loses the shop's thread at once" do
    before { say(thread, support, "Private note about the shop") }

    shared_examples "no access" do
      it "not in any inbox, not readable, not writable, not counted" do
        expect(inbox_ids(leaver)).not_to include(thread.id)
        expect(archived_ids(leaver)).not_to include(thread.id)

        get "/api/v1/conversations/#{thread.id}", headers: h(leaver)
        expect(response).to have_http_status(:not_found)
        get "/api/v1/conversations/#{thread.id}/messages", headers: h(leaver)
        expect(response).to have_http_status(:not_found)
        post "/api/v1/conversations/#{thread.id}/messages", params: { body: "hi" }, headers: h(leaver)
        expect(response.status).to be_in([ 403, 404 ])
        put "/api/v1/conversations/#{thread.id}/archive", headers: h(leaver)
        expect(response.status).to be_in([ 403, 404 ])
        post "/api/v1/support_conversation", params: { shop_id: shop.id }, headers: h(leaver)
        expect(response).to have_http_status(:forbidden)

        get "/api/v1/users/me", headers: h(leaver)
        expect(json["user"]["unread_counts"].to_h.fetch("shops", {})).not_to have_key(shop.id.to_s)
        expect(json["user"]["unread_counts"].to_h.fetch("support", 0)).to eq(0)
      end
    end

    context "Staff leaves" do
      let(:leaver) { staff.tap { shop.leave!(staff) } }

      it_behaves_like "no access"
    end

    context "a manager is removed by the owner" do
      let(:leaver) { manager.tap { shop.remove_team_member!(manager, by: owner) } }

      it_behaves_like "no access"
    end

    context "the old owner, a manager after a transfer, leaves" do
      let(:leaver) do
        shop.transfer_ownership!(manager, by: owner)
        owner.tap { shop.reload.leave!(owner) }
      end

      it_behaves_like "no access"
    end

    it "their earlier messages stay in the thread for the team, with who wrote them" do
      say(thread, staff, "Our logo will not upload")
      shop.leave!(staff)
      get "/api/v1/conversations/#{thread.id}/messages", headers: h(owner)
      mine = json["messages"].find { |m| m["body"] == "Our logo will not upload" }
      expect(mine).to be_present
      expect(mine["sent_by"]).to include("id" => staff.id)
    end
  end
end
