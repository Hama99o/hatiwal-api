require "swagger_helper"

# Support messaging, client contract (docs/SUPPORT_MESSAGING.md).
#
# The v1.0.4 app is live, sends no version header, and is served exactly what
# the new app is served — so everything here is ADDITIVE: listing threads must
# come back byte-for-byte as before, plus one `kind` key.
RSpec.describe "Api::V1::SupportConversations", type: :request do
  include ActiveJob::TestHelper

  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  path "/api/v1/support_conversation" do
    post "open (or return) the caller's thread with Hatiwal Support" do
      tags "Conversations"
      description "Idempotent. Creates the caller's support conversation on first call, returns it after. " \
                  "Rendered like GET /conversations/:id (kind: \"support\", listing: null, viewer_role: null). " \
                  "Owner, 2026-10-12: Support is per identity. Without shop_id, the caller's own thread (Buyer " \
                  "mode and Seller as Me); with shop_id, that SHOP's thread (members only, 403 otherwise), shared " \
                  "by its team and shown only while that shop is selected. GET /conversations lists each identity's " \
                  "thread by its last message like any chat, not pinned (owner, 2026-10-08; role=buying, " \
                  "role=selling&shop_id=none, role=selling&shop_id=<id>). It can be archived, never deleted. " \
                  "me.unread_counts.support is the person's thread's unread (also inside buying)."
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :shop_id, in: :query, type: :integer, required: false,
                description: "A shop the caller is a member of: that shop's own Support thread"

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:shop_id)        { nil }

      response "403", "shop_id names a shop the caller is not a member of" do
        let(:shop_id) { create(:shop).id }
        run_test!
      end

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }

        run_test!
      end

      response "200", "the caller's support thread" do
        run_test! do |response|
          c = JSON.parse(response.body)["conversation"]
          expect(c["kind"]).to eq("support")
          expect(c["listing"]).to be_nil
          # Deliberately true — see the serializer: a wrong banner beats a crash.
          expect(c["listing_deleted"]).to be(true)
          expect(c["viewer_role"]).to be_nil
          expect(c["other_participant"]).to include("name" => "Hatiwal Support", "verified" => true)
          expect(c["other_participant"].keys).to match_array(%w[id name city verified avatar_url])
          expect(c["blocked_with_participant"]).to be(false)
        end
      end
    end
  end

  def open_support_id
    post "/api/v1/support_conversation", headers: headers
    JSON.parse(response.body).dig("conversation", "id")
  end

  describe "behaviour" do
    def open_support
      post "/api/v1/support_conversation", headers: headers
      JSON.parse(response.body)["conversation"]
    end

    it "is idempotent: one thread per user" do
      first = open_support
      second = open_support

      expect(second["id"]).to eq(first["id"])
      expect(Conversation.kind_support.where(buyer_id: user.id).count).to eq(1)
    end

    it "creates exactly one Support account across many users" do
      open_support
      post "/api/v1/support_conversation", headers: auth_headers_for(create(:user))

      expect(User.where(support_account: true).count).to eq(1)
    end

    it "accepts a text message and refuses an offer" do
      id = open_support["id"]

      post "/api/v1/conversations/#{id}/messages", params: { body: "I can't log in on my phone" }, headers: headers
      expect(response).to have_http_status(:created)

      post "/api/v1/conversations/#{id}/messages", params: { body: "100|AFN|1", kind: "offer" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    # Owner, 2026-10-08: no longer pinned on top.
    it "sorts the support thread by its last message, like any other chat" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      busy = create(:conversation, buyer: user, listing: listing, last_message_at: 1.minute.ago)
      support_id = open_support["id"]
      Conversation.find(support_id).update!(last_message_at: 3.days.ago)

      get "/api/v1/conversations", headers: headers
      expect(JSON.parse(response.body)["conversations"].map { |c| c["id"] }).to eq([ busy.id, support_id ])

      Conversation.find(support_id).update!(last_message_at: Time.current)
      get "/api/v1/conversations", headers: headers
      expect(JSON.parse(response.body)["conversations"].map { |c| c["id"] }).to eq([ support_id, busy.id ])
    end

    # Search is SELECT DISTINCT; the support pin must not break it (it did, once).
    it "keeps inbox search working with a support thread present" do
      support_id = open_support["id"]

      get "/api/v1/conversations", params: { search: "Support" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["conversations"].map { |c| c["id"] }).to eq([ support_id ])
    end

    # Owner, 2026-10-12: the person's own Support thread belongs to Buyer mode
    # AND Seller as Me, so both role views carry it, once each.
    it "lists the person's support thread once in the Buying and Selling views" do
      support_id = open_support["id"]

      %w[buying selling].each do |role|
        get "/api/v1/conversations", params: { role: role }, headers: headers
        ids = JSON.parse(response.body)["conversations"].map { |c| c["id"] }
        expect(ids.count(support_id)).to eq(1)
      end
    end

    it "refuses blocking the Support account" do
      open_support
      post "/api/v1/users/#{User.support_account!.id}/block", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(user.blocked?(User.support_account!)).to be(false)
    end

    it "refuses reporting the Support account" do
      open_support
      post "/api/v1/reports", headers: headers, params: {
        report: { reportable_type: User.name, reportable_id: User.support_account!.id, reason: "spam" }
      }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "archiving and deleting a support thread" do
    let(:support) { User.support_account! }

    def inbox_ids(params = {})
      get "/api/v1/conversations", params: params, headers: headers
      JSON.parse(response.body)["conversations"].map { |c| c["id"] }
    end

    def support_reply(thread, body = "We're on it")
      create(:message, conversation: thread, user: support, body: body)
    end

    it "brings an archived thread back when Support replies, still UNREAD" do
      thread = Conversation.find(open_support_id)
      put "/api/v1/conversations/#{thread.id}/archive", headers: headers
      expect(inbox_ids).not_to include(thread.id)

      support_reply(thread)

      expect(inbox_ids).to include(thread.id)
      get "/api/v1/conversations/#{thread.id}", headers: headers
      expect(JSON.parse(response.body)["conversation"]["unread_count"]).to eq(1)
    end

    it "brings it back when the USER writes into an archived thread too" do
      thread = Conversation.find(open_support_id)
      thread.archive_for!(user)

      create(:message, conversation: thread, user: user, body: "one more thing")

      expect(thread.reload.archived_for?(user)).to be(false)
    end

    # Owner, 2026-10-08: archive yes, delete never.
    it "archives it (gone from the inbox, in Archived), but refuses deleting it with a code" do
      thread = Conversation.find(open_support_id)

      put "/api/v1/conversations/#{thread.id}/archive", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(inbox_ids).not_to include(thread.id)
      expect(inbox_ids(archived: true)).to include(thread.id)

      delete "/api/v1/conversations/#{thread.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["code"]).to eq("support_not_deletable")
      expect(thread.reload.deleted_for?(user)).to be(false)
      expect(Conversation.exists?(thread.id)).to be(true)
    end

    it "still deletes a LISTING thread" do
      convo = create(:conversation, buyer: user, listing: create(:listing, :active))
      delete "/api/v1/conversations/#{convo.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    # Threads deleted before deleting was refused still come back.
    it "brings an older DELETED thread back on a new message, and on Contact support" do
      thread = Conversation.find(open_support_id)
      thread.delete_for!(user)
      expect(inbox_ids).not_to include(thread.id)

      support_reply(thread)
      expect(inbox_ids).to include(thread.id)

      thread.delete_for!(user)
      expect(open_support_id).to eq(thread.id)
      expect(inbox_ids).to include(thread.id)
    end

    # Owner, 2026-10-08: any new Support message brings an archived thread
    # back, with its badge; while archived, its unread does not count.
    it "a Support NOTICE (SupportNoticeJob) brings it back, unread, and the badge with it" do
      thread = Conversation.find(open_support_id)
      support_reply(thread)
      put "/api/v1/conversations/#{thread.id}/archive", headers: headers
      expect(user.reload.unread_counts[:support]).to eq(0)

      user.update_column(:verified, true)
      SupportNoticeJob.perform_now(user.id, "user_verified")

      expect(inbox_ids).to include(thread.id)
      expect(user.reload.unread_counts[:support]).to eq(2)
    end

    it "an ADMIN reply (Admin::SendMessage.reply) brings it back, unread" do
      thread = Conversation.find(open_support_id)
      put "/api/v1/conversations/#{thread.id}/archive", headers: headers

      Admin::SendMessage.reply(admin: create(:admin_user), user: user, body: "Fixed it for you").call

      expect(inbox_ids).to include(thread.id)
      expect(user.reload.unread_counts[:support]).to eq(1)
    end

    # Per identity: a SHOP's Support thread is archived on the team's side and
    # comes back for the team on the shop's next notice; the person's own
    # thread is untouched by it.
    it "per identity: a shop notice brings the SHOP's archived thread back, not the person's" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
      shop = create(:shop, owner: user, name: "Kabul Cosmetics")
      own = Conversation.find(open_support_id)
      post "/api/v1/support_conversation", params: { shop_id: shop.id }, headers: headers
      shop_thread = Conversation.find(JSON.parse(response.body).dig("conversation", "id"))
      [ own, shop_thread ].each { |t| put "/api/v1/conversations/#{t.id}/archive", headers: headers }
      expect(shop_thread.reload.archived_for?(user)).to be(true)

      joiner = create(:user, :confirmed, firstname: "Ali", lastname: "Khan")
      create(:shop_invite, shop: shop).accept!(joiner)
      perform_enqueued_jobs(only: SupportNoticeJob)

      expect(shop_thread.reload.archived_for?(user)).to be(false)
      expect(inbox_ids(role: "selling", shop_id: shop.id)).to include(shop_thread.id)
      expect(own.reload.archived_for?(user)).to be(true)
      expect(user.reload.unread_counts[:shops][shop.id.to_s]).to eq(1)
    end

    it "never hides the thread from the admin, archived or deleted" do
      thread = Conversation.find(open_support_id)
      thread.archive_for!(user)

      expect(Conversation.kind_support).to include(thread)
    end

    # Pins today's behaviour so resurfacing can't spread to listing threads by
    # accident — changing that is a separate decision.
    it "leaves an archived LISTING thread archived when the other side replies" do
      seller = create(:user)
      convo = create(:conversation, buyer: user, listing: create(:listing, :active, user: seller))
      convo.archive_for!(user)

      create(:message, conversation: convo, user: seller, body: "still available")

      expect(convo.reload.archived_for?(user)).to be(true)
    end
  end

  # The guarantee v1.0.4 depends on: nothing about an EXISTING listing thread
  # changes except one added key.
  describe "listing threads are unchanged" do
    let(:seller)  { create(:user) }
    let(:listing) { create(:listing, :active, user: seller) }
    let!(:conversation) { create(:conversation, buyer: user, listing: listing) }

    it "adds only `kind`, and keeps viewer_role a string" do
      get "/api/v1/conversations", headers: headers
      row = JSON.parse(response.body)["conversations"].first
      expect(row["kind"]).to eq("listing")
      expect(row["viewer_role"]).to eq("buyer")

      get "/api/v1/conversations/#{conversation.id}", headers: headers
      detail = JSON.parse(response.body)["conversation"]
      expect(detail["kind"]).to eq("listing")
      expect(detail["viewer_role"]).to eq("buyer")
      expect(detail["listing"]).to include("id" => listing.id)
    end

    it "creates no support thread as a side effect of anything existing" do
      get "/api/v1/conversations", headers: headers
      expect(Conversation.kind_support.count).to eq(0)
    end
  end
end
