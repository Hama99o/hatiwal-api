require "rails_helper"

# Owner, 2026-10-12 (docs/OWNER_ITEMS_2026-10-12.md, item 4): Hatiwal Support is
# SEPARATED per identity. A person's own thread shows in Buyer mode and Seller as
# Me; each shop has its own thread, shown only while that shop is selected, read
# and answered by its whole team. Nothing crosses, and badges count only the
# current identity (+ its Support).
RSpec.describe "Support per identity", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  let(:owner) { create(:user, firstname: "Tamana", lastname: "Owner", preferred_language: "en") }
  let(:shop) { create(:shop, owner: owner, name: "Kabul Cosmetics") }
  let(:staff) { create(:user, firstname: "Ali", lastname: "Staff").tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
  let(:other_shop) { create(:shop, owner: create(:user), name: "Herat Phones") }
  let(:support) { User.support_account! }

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user)

  def inbox_ids(user, **params)
    get "/api/v1/conversations", params: params, headers: h(user)
    json["conversations"].pluck("id")
  end

  def say(thread, author, body = "Note")
    thread.messages.create!(user: author, kind: :text, body: body)
  end

  describe "POST /api/v1/support_conversation" do
    it "without shop_id: the person's own thread (Support on the seller side)" do
      post "/api/v1/support_conversation", headers: h(owner)
      thread = Conversation.find(json["conversation"]["id"])
      expect(thread).to have_attributes(kind: "support", shop_id: nil, buyer_id: owner.id, seller_id: support.id)
    end

    it "with shop_id: the shop's own thread, for any member, the same one each time" do
      post "/api/v1/support_conversation", params: { shop_id: shop.id }, headers: h(staff)
      first = json["conversation"]["id"]
      expect(Conversation.find(first)).to have_attributes(kind: "support", shop_id: shop.id, buyer_id: support.id, seller_id: owner.id)
      expect(json["conversation"]).to include("shop_chat" => false, "kind" => "support")
      expect(json["conversation"]["other_participant"]).to include("name" => "Hatiwal Support")

      post "/api/v1/support_conversation", params: { shop_id: shop.id }, headers: h(owner)
      expect(json["conversation"]["id"]).to eq(first)
    end

    it "refuses a shop the caller is not in" do
      post "/api/v1/support_conversation", params: { shop_id: other_shop.id }, headers: h(owner)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the inbox shows each identity's Support, never another's" do
    let!(:person_thread) { Conversation.support_thread_for!(owner) }
    let!(:shop_thread) { Conversation.shop_support_thread_for!(shop) }
    let!(:other_thread) { Conversation.shop_support_thread_for!(other_shop) }
    let!(:staff_thread) { Conversation.support_thread_for!(staff) }

    before { [ person_thread, shop_thread, other_thread, staff_thread ].each { |t| say(t, support) } }

    it "Buyer mode: the person's own thread only, pinned first" do
      ids = inbox_ids(owner, role: "buying")
      expect(ids.first).to eq(person_thread.id)
      expect(ids).not_to include(shop_thread.id, other_thread.id, staff_thread.id)
    end

    it "Seller as Me: the person's own thread only" do
      ids = inbox_ids(owner, role: "selling", shop_id: "none")
      expect(ids).to include(person_thread.id)
      expect(ids).not_to include(shop_thread.id, other_thread.id)
    end

    it "a shop selected: that shop's thread only, for the owner and for staff" do
      expect(inbox_ids(owner, role: "selling", shop_id: shop.id)).to eq([ shop_thread.id ])
      expect(inbox_ids(staff, role: "selling", shop_id: shop.id)).to eq([ shop_thread.id ])
    end

    it "a member's own Buyer mode never shows the shop's thread; a stranger never sees it at all" do
      expect(inbox_ids(staff, role: "buying")).to eq([ staff_thread.id ])
      stranger = create(:user)
      expect(inbox_ids(stranger)).not_to include(shop_thread.id, person_thread.id)
      get "/api/v1/conversations/#{shop_thread.id}", headers: h(stranger)
      expect(response).to have_http_status(:not_found)
    end

    it "search inside a shop's view never finds another identity's Support" do
      say(person_thread, support, "personal secret")
      expect(inbox_ids(owner, role: "selling", shop_id: shop.id, search: "secret")).to eq([])
    end

    it "badges: buying and support count the person's thread; the shop's entry counts the shop's thread" do
      get "/api/v1/users/me", headers: h(owner)
      counts = json["user"]["unread_counts"]
      expect(counts).to include("support" => 1, "buying" => 1, "selling_me" => 0)
      expect(counts["shops"]).to eq(shop.id.to_s => 1)
    end

    it "the team shares the shop's thread: a member's reply is not unread for the others, Support's is" do
      say(shop_thread, staff, "We need help with the badge")
      get "/api/v1/users/me", headers: h(owner)
      expect(json["user"]["unread_counts"]["shops"]).to eq(shop.id.to_s => 1) # Support's note, not Ali's

      get "/api/v1/conversations/#{shop_thread.id}/messages", headers: h(owner)
      ali = json["messages"].find { |m| m["body"] == "We need help with the badge" }
      expect(ali["sent_by"]).to include("id" => staff.id) # the team sees who replied
    end
  end

  describe "notices go to the right thread" do
    def run_jobs = perform_enqueued_jobs(only: SupportNoticeJob)
    def bodies(thread) = thread&.messages.to_a.map(&:body)

    it "a shop's verification and a new member go to the shop's thread; personal notices to the person's" do
      member = create(:user, firstname: "Gul", lastname: "Khan", preferred_language: "en")
      create(:shop_invite, shop: shop).accept!(member)
      owner.update!(verified: true)
      SupportNoticeJob.enqueue(owner, :user_verified)
      run_jobs

      shop_thread = Conversation.shop_support.find_by(shop_id: shop.id)
      person_thread = Conversation.person_support.find_by(buyer_id: owner.id)
      expect(bodies(shop_thread)).to eq([ "Gul Khan joined Kabul Cosmetics as Staff." ])
      expect(bodies(person_thread)).to eq([ I18n.t("support.notices.user_verified", locale: :en, name: "Tamana") ])
      # The new member's welcome is about them: their own thread.
      expect(Conversation.person_support.find_by(buyer_id: member.id).messages.count).to eq(1)
    end

    it "a shop verification decision lands in the shop's thread, written by Support" do
      shop = create(:shop, :verification_eligible, owner: owner)
      request = create(:shop_verification_request, shop: shop)
      request.reject!(admin: create(:admin_user), reason_code: "photo_not_clear")
      run_jobs

      thread = Conversation.shop_support.find_by(shop_id: shop.id)
      expect(thread.messages.sole.user).to eq(support)
      expect(Conversation.person_support.find_by(buyer_id: owner.id)).to be_nil
    end
  end

  describe "admin" do
    let(:admin) { create(:admin_user) }
    let!(:shop_thread) { Conversation.shop_support_thread_for!(shop) }

    before do
      say(shop_thread, staff, "Our logo will not upload")
      sign_in admin, scope: :admin_user
    end

    it "lists the shop's thread under the shop's name, awaiting a reply" do
      get admin_support_conversations_path
      expect(response.body).to include("Kabul Cosmetics")
    end

    it "shows which member wrote each message, and their role" do
      get admin_support_conversation_path(shop_thread)
      expect(response.body).to include("Support — shop", "Ali Staff", "Staff")
      expect(shop_thread.messages.reload.first.read_at).to be_present # opening it reads the team's messages
    end

    it "a reply goes to the whole team, written by Support and signed by the admin" do
      expect do
        post reply_admin_support_conversation_path(shop_thread), params: { body: "Try a smaller image" }
      end.to have_enqueued_job(SendMessagePushJob)
      reply = shop_thread.messages.order(:id).last
      expect(reply).to have_attributes(user_id: support.id, admin_user_id: admin.id, body: "Try a smaller image")
    end
  end

  it "a transfer hands the shop's thread to the new owner with the shop" do
    thread = Conversation.shop_support_thread_for!(shop)
    shop.transfer_ownership!(staff, by: owner)
    expect(thread.reload.seller_id).to eq(staff.id)
    expect(inbox_ids(staff, role: "selling", shop_id: shop.id)).to include(thread.id)
  end

  it "the 2026-10-07 mixed messages move to the shop's thread (migration)" do
    require Rails.root.join("db/migrate/20261007120000_support_thread_per_shop.rb").to_s
    person = Conversation.support_thread_for!(owner)
    keep = say(person, owner, "about me")
    moved = say(person, owner, "about my shop")
    moved.update_columns(context: { "mode" => "seller", "shop_id" => shop.id, "role" => "owner" })

    SupportThreadPerShop.new.send(:move_shop_messages_out_of_person_threads)
    SupportThreadPerShop.new.send(:move_shop_messages_out_of_person_threads) # idempotent

    shop_thread = Conversation.shop_support.find_by!(shop_id: shop.id)
    expect(shop_thread.messages.pluck(:id)).to eq([ moved.id ])
    expect(person.messages.pluck(:id)).to eq([ keep.id ])
    expect(shop_thread).to have_attributes(buyer_id: support.id, seller_id: owner.id)
  end
end
