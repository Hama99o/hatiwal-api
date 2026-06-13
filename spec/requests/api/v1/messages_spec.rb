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

    it "returns messages ordered newest first for a participant" do
      first  = create(:message, conversation: conversation, user: buyer, created_at: 2.hours.ago)
      second = create(:message, conversation: conversation, user: seller, created_at: 1.hour.ago)

      get "/api/v1/conversations/#{conversation.id}/messages", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["messages"].map { |m| m["id"] }
      expect(ids).to eq([ second.id, first.id ])
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
  end
end
