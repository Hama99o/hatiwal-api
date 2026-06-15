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

    it "forbids starting a conversation on your own listing" do
      own = create(:listing, :active, user: buyer)
      post "/api/v1/listings/#{own.id}/conversations",
           params: { message: "hi" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids starting a conversation on a non-active listing" do
      draft = create(:listing, :draft, user: seller)
      post "/api/v1/listings/#{draft.id}/conversations",
           params: { message: "hi" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns the existing conversation instead of duplicating" do
      create(:conversation, buyer: buyer, listing: listing)
      expect do
        post "/api/v1/listings/#{listing.id}/conversations",
             params: { message: "hello again" }, headers: headers, as: :json
      end.not_to change(Conversation, :count)
      expect(response).to have_http_status(:created)
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
end
