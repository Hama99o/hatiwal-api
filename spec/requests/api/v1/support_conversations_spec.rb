require "swagger_helper"

# Support messaging, client contract (docs/SUPPORT_MESSAGING.md).
#
# The v1.0.4 app is live, sends no version header, and is served exactly what
# the new app is served — so everything here is ADDITIVE: listing threads must
# come back byte-for-byte as before, plus one `kind` key.
RSpec.describe "Api::V1::SupportConversations", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  path "/api/v1/support_conversation" do
    post "open (or return) the caller's thread with Hatiwal Support" do
      tags "Conversations"
      description "Idempotent. Creates the caller's support conversation on first call, returns it after. " \
                  "Rendered like GET /conversations/:id (kind: \"support\", listing: null, viewer_role: null)."
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

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

    it "pins the support thread first in the inbox" do
      seller  = create(:user)
      listing = create(:listing, :active, user: seller)
      busy = create(:conversation, buyer: user, listing: listing, last_message_at: 1.minute.ago)
      support_id = open_support["id"]
      Conversation.find(support_id).update!(last_message_at: 3.days.ago)

      get "/api/v1/conversations", headers: headers
      ids = JSON.parse(response.body)["conversations"].map { |c| c["id"] }

      expect(ids.first).to eq(support_id)
      expect(ids).to include(busy.id)
    end

    # Search is SELECT DISTINCT; the support pin must not break it (it did, once).
    it "keeps inbox search working with a support thread present" do
      support_id = open_support["id"]

      get "/api/v1/conversations", params: { search: "Support" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["conversations"].map { |c| c["id"] }).to eq([ support_id ])
    end

    it "keeps the support thread out of the Buying and Selling tabs" do
      support_id = open_support["id"]

      %w[buying selling].each do |role|
        get "/api/v1/conversations", params: { role: role }, headers: headers
        ids = JSON.parse(response.body)["conversations"].map { |c| c["id"] }
        expect(ids).not_to include(support_id)
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
