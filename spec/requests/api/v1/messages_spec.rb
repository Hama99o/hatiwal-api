require "rails_helper"

RSpec.describe "Api::V1::Messages", type: :request do
  let(:buyer)        { create(:user) }
  let(:seller)       { create(:user) }
  let(:listing)      { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }
  let(:headers)      { auth_headers_for(buyer) }

  describe "GET /api/v1/conversations/:conversation_id/messages" do
    it "requires authentication" do
      get "/api/v1/conversations/#{conversation.id}/messages", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # TASK-K418: messages must be returned oldest-first (ascending created_at)
    # so a chat transcript reads chronologically in the mobile client.
    it "returns messages ordered oldest first (ascending) for a participant" do
      first  = create(:message, conversation: conversation, user: buyer,  created_at: 2.hours.ago)
      second = create(:message, conversation: conversation, user: seller, created_at: 1.hour.ago)

      get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["messages"].map { |m| m["id"] }
      expect(ids).to eq([ first.id, second.id ])
    end

    # TASK-K418: eager-loading must eliminate per-message User queries.
    # Seed the conversation with 10 messages from 2 different senders and assert
    # the total SQL query count stays constant — i.e. does NOT grow with message count.
    it "issues a constant number of SQL queries regardless of message count (no N+1)" do
      sender_a = buyer
      sender_b = seller

      # Create 10 messages alternating between the two senders.
      10.times do |i|
        sender = i.even? ? sender_a : sender_b
        create(:message, conversation: conversation, user: sender, created_at: i.hours.ago)
      end

      # Warm up any connection / schema caches so only data queries are counted.
      get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      # Now measure the actual query count for the 10-message page.
      query_count_10 = 0
      counter = ->(*, **) { query_count_10 += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json
      end

      # Add 5 more messages (15 total) from both senders and measure again.
      5.times do |i|
        sender = i.odd? ? sender_a : sender_b
        create(:message, conversation: conversation, user: sender)
      end

      query_count_15 = 0
      counter15 = ->(*, **) { query_count_15 += 1 }
      ActiveSupport::Notifications.subscribed(counter15, "sql.active_record") do
        get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json
      end

      # The query count must not grow per-message.  With a perfect eager-load
      # the delta should be zero; we allow a tolerance of ±2 to account for
      # any Pagy metadata or schema-introspection queries that Rails may emit.
      expect(query_count_15).to be <= (query_count_10 + 2),
        "Expected query count to stay constant but it grew from #{query_count_10} " \
        "(10 messages) to #{query_count_15} (15 messages) — N+1 is still present"
    end

    it "404s for a non-participant (scoped out)" do
      outsider_headers = auth_headers_for(create(:user))
      get "/api/v1/conversations/#{conversation.id}/messages", headers: outsider_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/conversations/:conversation_id/messages" do
    it "creates a message authored by the current user" do
      expect do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "Sounds good, where can we meet?" }, headers: headers, as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["message"]
      expect(body["body"]).to eq("Sounds good, where can we meet?")
      expect(body["sender"]["id"]).to eq(buyer.id)
      expect(body).to have_key("attachment_url")
    end

    it "creates a document message with an attached file" do
      file = fixture_file_upload(
        Rails.root.join("spec/fixtures/files/test_image.jpg"),
        "image/jpeg"
      )

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Here is the photo", kind: "image_message", attachment: file },
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["message"]
      expect(body["kind"]).to eq("image_message")
      expect(body["attachment_url"]).to be_present
    end

    it "creates a meetup proposal message" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Cafe Aria | Tomorrow 3pm", kind: "meetup_proposal" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["kind"]).to eq("meetup_proposal")
    end

    it "creates a meetup accepted response" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Cafe Aria | Tomorrow 3pm", kind: "meetup_accepted" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["kind"]).to eq("meetup_accepted")
    end

    it "links an accept/decline response to the specific proposal" do
      proposal = conversation.messages.create!(user: buyer, kind: :meetup_proposal, body: "Cafe Aria | 3pm")

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Cafe Aria | 3pm", kind: "meetup_declined", responds_to_id: proposal.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["responds_to_id"]).to eq(proposal.id)
    end

    it "accepts an offer (linked to the offer message)" do
      offer = conversation.messages.create!(user: buyer, kind: :offer, body: "7|AFN|11")

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "7|AFN|11", kind: "offer_accepted", responds_to_id: offer.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["message"]
      expect(body["kind"]).to eq("offer_accepted")
      expect(body["responds_to_id"]).to eq(offer.id)
    end

    it "declines an offer" do
      offer = conversation.messages.create!(user: buyer, kind: :offer, body: "7|AFN|11")

      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "7|AFN|11", kind: "offer_declined", responds_to_id: offer.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["kind"]).to eq("offer_declined")
    end

    it "creates a meetup declined response" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Cafe Aria | Tomorrow 3pm", kind: "meetup_declined" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]["kind"]).to eq("meetup_declined")
    end

    it "updates the conversation's last_message_at" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "ping" }, headers: headers, as: :json
      expect(conversation.reload.last_message_at).to be_present
    end

    it "422s on a blank body" do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "" }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    context "responds_to_id cross-conversation guard (TASK-K072)" do
      let(:other_listing)      { create(:listing, :active, user: seller) }
      let(:other_conversation) { create(:conversation, buyer: buyer, listing: other_listing) }

      it "422s when responds_to_id points at a message in a DIFFERENT conversation" do
        foreign_proposal = create(:message, conversation: other_conversation,
                                            user: buyer, kind: :meetup_proposal,
                                            body: "Park | 5pm")

        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "Park | 5pm", kind: "meetup_accepted",
                       responds_to_id: foreign_proposal.id },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(Message.where(responds_to_id: foreign_proposal.id,
                             conversation: conversation)).to be_empty
      end

      it "422s when responds_to_id references a non-existent message id" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "Confirmed", kind: "meetup_accepted", responds_to_id: 999_999 },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "succeeds when responds_to_id points at a message in the SAME conversation" do
        proposal = create(:message, conversation: conversation, user: buyer,
                                    kind: :meetup_proposal, body: "Cafe | 3pm")

        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "Cafe | 3pm", kind: "meetup_accepted",
                       responds_to_id: proposal.id },
             headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)["message"]
        expect(body["responds_to_id"]).to eq(proposal.id)
        expect(body["kind"]).to eq("meetup_accepted")
      end
    end

    # ── TASK-K071 kind-whitelist security ────────────────────────────────────
    context "kind whitelist (TASK-K071)" do
      it "rejects kind:'system' with 422 and does not persist the message" do
        expect do
          post "/api/v1/conversations/#{conversation.id}/messages",
               params: { body: "You have been selected as a winner!", kind: "system" },
               headers: headers, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create a system message when kind:'system' is sent" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "Official notice", kind: "system" },
             headers: headers, as: :json

        expect(Message.where(kind: :system)).to be_empty
      end

      it "rejects an unknown/arbitrary kind with 422" do
        expect do
          post "/api/v1/conversations/#{conversation.id}/messages",
               params: { body: "test", kind: "hacker_kind" },
               headers: headers, as: :json
        end.not_to change(Message, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "defaults to kind:'text' when no kind is supplied" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "hello" }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)["message"]["kind"]).to eq("text")
      end

      Message::USER_SENDABLE_KINDS.each do |allowed_kind|
        it "accepts kind:'#{allowed_kind}'" do
          post "/api/v1/conversations/#{conversation.id}/messages",
               params: { body: "body for #{allowed_kind}", kind: allowed_kind },
               headers: headers, as: :json

          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)["message"]["kind"]).to eq(allowed_kind)
        end
      end
    end
    # ── end TASK-K071 ─────────────────────────────────────────────────────────

    it "forbids sending into a closed conversation" do
      closed = create(:conversation, buyer: buyer, listing: listing, status: :closed)
      post "/api/v1/conversations/#{closed.id}/messages",
           params: { body: "hi" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "404s when a non-participant tries to send" do
      outsider_headers = auth_headers_for(create(:user))
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "hi" }, headers: outsider_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    # ── TASK-K739: block guard on open conversations ──────────────────────────

    context "when buyer has blocked seller (TASK-K739)" do
      before { create(:block, blocker: buyer, blocked: seller) }

      it "forbids the seller (blocked user) from sending into the open conversation" do
        seller_headers = auth_headers_for(seller)
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "hello from seller" }, headers: seller_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "forbids the buyer (blocker) from sending into the open conversation" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "hello from buyer" }, headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when seller has blocked buyer (TASK-K739)" do
      before { create(:block, blocker: seller, blocked: buyer) }

      it "forbids the buyer (blocked user) from sending into the open conversation" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "hello from buyer" }, headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "forbids the seller (blocker) from sending into the open conversation" do
        seller_headers = auth_headers_for(seller)
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "hello from seller" }, headers: seller_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when no block exists between participants (TASK-K739)" do
      it "allows both buyer and seller to send in an open conversation" do
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "from buyer" }, headers: headers, as: :json
        expect(response).to have_http_status(:created)

        seller_headers = auth_headers_for(seller)
        post "/api/v1/conversations/#{conversation.id}/messages",
             params: { body: "from seller" }, headers: seller_headers, as: :json
        expect(response).to have_http_status(:created)
      end
    end

    context "when conversation is closed and a block exists (TASK-K739)" do
      before do
        create(:block, blocker: buyer, blocked: seller)
      end

      it "rejects with forbidden regardless of block state" do
        closed = create(:conversation, buyer: buyer, listing: listing, status: :closed)
        post "/api/v1/conversations/#{closed.id}/messages",
             params: { body: "hi" }, headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    # ── end TASK-K739 ─────────────────────────────────────────────────────────
  end

  describe "PUT /api/v1/conversations/:conversation_id/messages/mark_read" do
    it "marks unread messages from the other participant as read" do
      create(:message, conversation: conversation, user: seller, read_at: nil)

      put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
          headers: headers, as: :json

      expect(response).to have_http_status(:no_content)
      expect(conversation.messages.where(user: seller).first.reload.read_at).to be_present
    end

    it "does not mark your own messages as read" do
      own_msg = create(:message, conversation: conversation, user: buyer, read_at: nil)

      put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
          headers: headers, as: :json

      expect(own_msg.reload.read_at).to be_nil
    end

    it "does not change read_at on already-read messages" do
      original_time = 1.hour.ago
      already_read = create(:message, conversation: conversation, user: seller,
                                      read_at: original_time)

      put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
          headers: headers, as: :json

      expect(already_read.reload.read_at.to_i).to eq(original_time.to_i)
    end

    it "requires authentication" do
      put "/api/v1/conversations/#{conversation.id}/messages/mark_read", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for non-participants" do
      outsider_headers = auth_headers_for(create(:user))
      put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
          headers: outsider_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    # TASK-M703: mark_read must issue exactly ONE UPDATE query regardless of
    # how many unread messages exist in the conversation.
    #
    # Strategy: count only UPDATE statements (to avoid coupling to the exact
    # number of SELECT/auth queries which may vary by Rails version), then
    # assert that count == 1 for both 10 and 15 unread messages.
    it "issues exactly one UPDATE query regardless of unread message count (no N+1)" do
      # Seed 12 unread messages from seller (other participant).
      12.times { create(:message, conversation: conversation, user: seller, read_at: nil) }

      # Warm-up: run once to prime any connection/schema caches.
      put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
          headers: headers, as: :json
      expect(response).to have_http_status(:no_content)

      # Reset: mark them all unread again so the action has work to do.
      conversation.messages.update_all(read_at: nil)

      # Count UPDATE statements for 12 unread messages.
      update_count_12 = 0
      update_counter  = lambda do |_name, _start, _finish, _id, payload|
        update_count_12 += 1 if payload[:sql].to_s.upcase.start_with?("UPDATE")
      end
      ActiveSupport::Notifications.subscribed(update_counter, "sql.active_record") do
        put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
            headers: headers, as: :json
      end

      # Add 3 more unread messages (15 total) and measure again.
      3.times { create(:message, conversation: conversation, user: seller, read_at: nil) }
      conversation.messages.update_all(read_at: nil)

      update_count_15 = 0
      update_counter2 = lambda do |_name, _start, _finish, _id, payload|
        update_count_15 += 1 if payload[:sql].to_s.upcase.start_with?("UPDATE")
      end
      ActiveSupport::Notifications.subscribed(update_counter2, "sql.active_record") do
        put "/api/v1/conversations/#{conversation.id}/messages/mark_read",
            headers: headers, as: :json
      end

      expect(update_count_12).to eq(1),
        "Expected exactly 1 UPDATE for 12 unread messages but got #{update_count_12}"
      expect(update_count_15).to eq(1),
        "Expected exactly 1 UPDATE for 15 unread messages but got #{update_count_15}"
    end
  end
end
