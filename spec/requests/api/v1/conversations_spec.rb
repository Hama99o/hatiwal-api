require "rails_helper"

RSpec.describe "Api::V1::Conversations", type: :request do
  let(:buyer)   { create(:user) }
  let(:seller)  { create(:user) }
  let(:listing) { create(:listing, :active, user: seller) }
  let(:headers) { auth_headers_for(buyer) }

  describe "GET /api/v1/conversations" do
    it "requires authentication" do
      get "/api/v1/conversations", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only the current user's conversations" do
      mine = create(:conversation, buyer: buyer, listing: listing)
      create(:conversation) # someone else's

      get "/api/v1/conversations", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["conversations"].map { |c| c["id"] }
      expect(ids).to eq([ mine.id ])
    end

    it "includes the last message body and kind for the preview" do
      conv = create(:conversation, buyer: buyer, listing: listing)
      conv.messages.create!(user: buyer, kind: :meetup_proposal, body: "Cafe | 3pm")

      get "/api/v1/conversations", headers: headers, as: :json

      row = JSON.parse(response.body)["conversations"].find { |c| c["id"] == conv.id }
      expect(row["last_message_body"]).to eq("Cafe | 3pm")
      expect(row["last_message_kind"]).to eq("meetup_proposal")
    end

    it "filters by listing_id when provided" do
      other_listing = create(:listing, :active, user: seller)
      conv_for_listing = create(:conversation, buyer: buyer, listing: listing)
      _conv_other      = create(:conversation, buyer: buyer, listing: other_listing)

      get "/api/v1/conversations?listing_id=#{listing.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["conversations"].map { |c| c["id"] }
      expect(ids).to eq([ conv_for_listing.id ])
    end

    it "does not fire extra queries per additional conversation row (no N+1)" do
      conv0 = create(:conversation, buyer: buyer, listing: listing)
      conv0.messages.create!(user: buyer, body: "hey 0", kind: :text)

      # Warm up Rails stack (schema introspection, token auth, etc.)
      get "/api/v1/conversations", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      queries_with_1 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_1 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/conversations", headers: headers, as: :json
      end

      5.times do |i|
        s = create(:user)
        l = create(:listing, :active, user: s)
        c = create(:conversation, buyer: buyer, listing: l)
        c.messages.create!(user: buyer, body: "hey #{i}", kind: :text)
      end

      queries_with_6 = 0
      ActiveSupport::Notifications.subscribed(
        ->(*) { queries_with_6 += 1 },
        "sql.active_record"
      ) do
        get "/api/v1/conversations", headers: headers, as: :json
      end
      expect(response).to have_http_status(:ok)

      # Adding 5 more rows (with distinct sellers/listings/messages) must not
      # grow the query count proportionally. All relationships are eager-loaded
      # (messages, listing, buyer/seller avatars) and block id-sets are preloaded
      # as Ruby Sets, so every load is a single batch IN-clause query regardless
      # of N. We allow a tolerance of +1 for DeviseTokenAuth token rotation, which
      # fires a single UPDATE on the first request after a token TTL boundary —
      # that overhead is O(1), not O(N). Any delta larger than 1 indicates a real
      # per-row regression.
      expect(queries_with_6).to be <= queries_with_1 + 1,
        "Expected constant query count (no N+1), " \
        "but got #{queries_with_1} queries with 1 conversation and " \
        "#{queries_with_6} with 6 conversations (delta #{queries_with_6 - queries_with_1})"
    end

    it "fires a constant number of block-table queries regardless of inbox size" do
      # Seed a conversation with a block so block rows actually exist
      create(:block, blocker: buyer, blocked: seller)
      conv0 = create(:conversation, buyer: buyer, listing: listing)
      conv0.messages.create!(user: buyer, body: "hey 0", kind: :text)

      # Warm up Rails stack
      get "/api/v1/conversations", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      block_queries_with_1 = 0
      subscriber = ->(*, payload) { block_queries_with_1 += 1 if payload[:sql].to_s.match?(/blocks/i) }
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get "/api/v1/conversations", headers: headers, as: :json
      end

      5.times do |i|
        s = create(:user)
        l = create(:listing, :active, user: s)
        c = create(:conversation, buyer: buyer, listing: l)
        c.messages.create!(user: buyer, body: "hey #{i}", kind: :text)
      end

      block_queries_with_6 = 0
      subscriber6 = ->(*, payload) { block_queries_with_6 += 1 if payload[:sql].to_s.match?(/blocks/i) }
      ActiveSupport::Notifications.subscribed(subscriber6, "sql.active_record") do
        get "/api/v1/conversations", headers: headers, as: :json
      end
      expect(response).to have_http_status(:ok)

      # Block-table queries must be constant (2: one SELECT for blocked_ids,
      # one SELECT for blocker_ids) regardless of how many conversations are in the
      # inbox.  Any growth here means the serializer fell back to per-row exists?
      # calls instead of the preloaded id-sets.
      expect(block_queries_with_6).to eq(block_queries_with_1),
        "Expected block-table query count to be constant (#{block_queries_with_1}) " \
        "but got #{block_queries_with_6} with 6 conversations"
    end
  end

  describe "blocked_with_participant flag — GET /api/v1/conversations (list)" do
    let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

    it "is false when neither party has blocked the other" do
      conversation

      get "/api/v1/conversations", headers: headers, as: :json

      row = JSON.parse(response.body)["conversations"].find { |c| c["id"] == conversation.id }
      expect(row["blocked_with_participant"]).to be false
    end

    it "is true when current_user (buyer) has blocked the other participant (seller)" do
      create(:block, blocker: buyer, blocked: seller)
      conversation

      get "/api/v1/conversations", headers: headers, as: :json

      row = JSON.parse(response.body)["conversations"].find { |c| c["id"] == conversation.id }
      expect(row["blocked_with_participant"]).to be true
    end

    it "is true when the other participant (seller) has blocked current_user (buyer)" do
      create(:block, blocker: seller, blocked: buyer)
      conversation

      get "/api/v1/conversations", headers: headers, as: :json

      row = JSON.parse(response.body)["conversations"].find { |c| c["id"] == conversation.id }
      expect(row["blocked_with_participant"]).to be true
    end
  end

  describe "GET /api/v1/conversations/:id" do
    let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

    it "returns the conversation for a participant" do
      get "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["conversation"]["id"]).to eq(conversation.id)
    end

    it "404s when a non-participant tries to view it (scoped out)" do
      outsider_headers = auth_headers_for(create(:user))
      get "/api/v1/conversations/#{conversation.id}", headers: outsider_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "includes blocked_with_participant false when neither party has blocked the other" do
      get "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["conversation"]
      expect(data["blocked_with_participant"]).to be false
    end

    it "includes blocked_with_participant true when current_user (buyer) blocked the seller" do
      create(:block, blocker: buyer, blocked: seller)

      get "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["conversation"]
      expect(data["blocked_with_participant"]).to be true
    end

    it "includes blocked_with_participant true when the seller blocked current_user (buyer)" do
      create(:block, blocker: seller, blocked: buyer)

      get "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["conversation"]
      expect(data["blocked_with_participant"]).to be true
    end

    # The thread screen relies on other_participant for the nav title, the
    # tap-to-seller-profile link, and the block toggle. The buyer viewing the
    # thread must see the seller as the other participant.
    it "includes other_participant (the seller, from the buyer's perspective)" do
      get "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      other = JSON.parse(response.body)["conversation"]["other_participant"]
      expect(other).to be_present
      expect(other["id"]).to eq(seller.id)
      expect(other["name"]).to eq(seller.full_name)
    end

    it "resolves other_participant relative to the viewer (seller sees the buyer)" do
      get "/api/v1/conversations/#{conversation.id}", headers: auth_headers_for(seller), as: :json

      expect(response).to have_http_status(:ok)
      other = JSON.parse(response.body)["conversation"]["other_participant"]
      expect(other["id"]).to eq(buyer.id)
    end
  end

  describe "DELETE /api/v1/conversations/:id" do
    let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

    it "allows the buyer to delete the conversation" do
      conversation # ensure record exists before measuring count

      expect do
        delete "/api/v1/conversations/#{conversation.id}", headers: headers, as: :json
      end.to change(Conversation, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "allows the seller to delete the conversation" do
      seller_headers = auth_headers_for(seller)
      conversation # ensure record exists before measuring count

      expect do
        delete "/api/v1/conversations/#{conversation.id}", headers: seller_headers, as: :json
      end.to change(Conversation, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "forbids a non-participant from deleting the conversation" do
      outsider_headers = auth_headers_for(create(:user))
      delete "/api/v1/conversations/#{conversation.id}", headers: outsider_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      delete "/api/v1/conversations/#{conversation.id}", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/listings/:listing_id/conversations" do
    it "starts a conversation with a first message" do
      expect do
        post "/api/v1/listings/#{listing.id}/conversations",
             params: { message: "Is this still available?" }, headers: headers, as: :json
      end.to change(Conversation, :count).by(1).and change(Message, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["conversation"]["id"]).to be_present
    end

    it "returns 422 and creates no Conversation when the listing owner tries to start a conversation on their own listing" do
      own = create(:listing, :active, user: buyer)
      expect do
        post "/api/v1/listings/#{own.id}/conversations",
             params: { message: "hi" }, headers: headers, as: :json
      end.not_to change(Conversation, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to be_present
    end

    it "forbids starting a conversation on a non-active listing" do
      draft = create(:listing, :draft, user: seller)
      post "/api/v1/listings/#{draft.id}/conversations",
           params: { message: "hi" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns the existing conversation (same id, no new record) instead of duplicating" do
      existing = create(:conversation, buyer: buyer, listing: listing)
      expect do
        post "/api/v1/listings/#{listing.id}/conversations",
             params: { message: "hello again" }, headers: headers, as: :json
      end.not_to change(Conversation, :count)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["conversation"]["id"]).to eq(existing.id)
    end

    it "422s when the message body is blank" do
      post "/api/v1/listings/#{listing.id}/conversations",
           params: { message: "" }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to be_present
    end

    context "when the buyer has blocked the seller" do
      before { create(:block, blocker: buyer, blocked: seller) }

      it "returns 422 and creates no Conversation rows" do
        expect do
          post "/api/v1/listings/#{listing.id}/conversations",
               params: { message: "Still available?" }, headers: headers, as: :json
        end.not_to change(Conversation, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to be_present
      end

      it "returns 422 and creates no Message rows" do
        expect do
          post "/api/v1/listings/#{listing.id}/conversations",
               params: { message: "Still available?" }, headers: headers, as: :json
        end.not_to change(Message, :count)
      end
    end

    context "when the buyer has been blocked by the seller" do
      before { create(:block, blocker: seller, blocked: buyer) }

      it "returns 422 and creates no Conversation rows" do
        expect do
          post "/api/v1/listings/#{listing.id}/conversations",
               params: { message: "Still available?" }, headers: headers, as: :json
        end.not_to change(Conversation, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to be_present
      end

      it "returns 422 and creates no Message rows" do
        expect do
          post "/api/v1/listings/#{listing.id}/conversations",
               params: { message: "Still available?" }, headers: headers, as: :json
        end.not_to change(Message, :count)
      end
    end
  end

  describe "PUT /api/v1/conversations/:id/mark_read" do
    let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

    context "when the buyer marks the conversation as read" do
      before do
        # Seller sends two unread messages (buyer has not read them)
        conversation.messages.create!(user: seller, body: "Hello", kind: :text)
        conversation.messages.create!(user: seller, body: "Still here?", kind: :text)
      end

      it "returns 204 no_content" do
        put "/api/v1/conversations/#{conversation.id}/mark_read", headers: headers, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "sets read_at on the other participant's unread messages" do
        put "/api/v1/conversations/#{conversation.id}/mark_read", headers: headers, as: :json
        expect(conversation.messages.where(read_at: nil).where.not(user_id: buyer.id).count).to eq(0)
      end

      it "reduces unread_count_for(buyer) to 0" do
        put "/api/v1/conversations/#{conversation.id}/mark_read", headers: headers, as: :json
        expect(conversation.reload.unread_count_for(buyer)).to eq(0)
      end

      it "does not touch messages authored by the buyer" do
        buyer_msg = conversation.messages.create!(user: buyer, body: "Hi", kind: :text)
        put "/api/v1/conversations/#{conversation.id}/mark_read", headers: headers, as: :json
        expect(buyer_msg.reload.read_at).to be_nil
      end
    end

    it "requires authentication" do
      put "/api/v1/conversations/#{conversation.id}/mark_read", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for a non-participant" do
      outsider_headers = auth_headers_for(create(:user))
      put "/api/v1/conversations/#{conversation.id}/mark_read", headers: outsider_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PUT /api/v1/conversations/:id/mark_unread" do
    let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }

    context "when the seller marks the conversation as unread" do
      let(:seller_headers) { auth_headers_for(seller) }

      before do
        # Buyer sends a message, seller has already read it
        msg = conversation.messages.create!(user: buyer, body: "Is this available?", kind: :text)
        msg.update!(read_at: Time.current)
      end

      it "returns 204 no_content" do
        put "/api/v1/conversations/#{conversation.id}/mark_unread", headers: seller_headers, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "restores unread_count_for(seller) to be > 0" do
        put "/api/v1/conversations/#{conversation.id}/mark_unread", headers: seller_headers, as: :json
        expect(conversation.reload.unread_count_for(seller)).to be > 0
      end

      it "clears read_at on the most recent inbound message only" do
        # Add a second message already read
        msg2 = conversation.messages.create!(user: buyer, body: "Hello?", kind: :text)
        msg2.update!(read_at: Time.current)

        put "/api/v1/conversations/#{conversation.id}/mark_unread", headers: seller_headers, as: :json

        # Only the most recent inbound message should have read_at cleared
        unread_count = conversation.messages.where(read_at: nil).where.not(user_id: seller.id).count
        expect(unread_count).to eq(1)
      end
    end

    it "requires authentication" do
      put "/api/v1/conversations/#{conversation.id}/mark_unread", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for a non-participant" do
      outsider_headers = auth_headers_for(create(:user))
      put "/api/v1/conversations/#{conversation.id}/mark_unread", headers: outsider_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
