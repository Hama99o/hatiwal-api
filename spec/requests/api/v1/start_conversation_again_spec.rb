require "rails_helper"

# Owner, 2026-10-12 (TestFlight 1.1.6): "when you send a message from a listing,
# the first time it works; the second time it goes to the message page but
# nothing shows, no error". Owner decision the same day: "make offer button work
# in second time also but not contact seller button".
# - Contact seller again: the buyer lands in the chat they already have, with
#   its history, and nothing is added (the typed text is not sent).
# - Make offer again: the app starts the chat (it already exists) and then posts
#   the offer, which must land in that chat, with no second greeting.
# - Neither is a new chat for the daily start limit.
RSpec.describe "Contacting the seller again from the listing", type: :request do
  include ActiveJob::TestHelper

  let(:seller)  { create(:user, :confirmed) }
  let(:buyer)   { create(:user, :confirmed) }
  let(:listing) { create(:listing, :active, user: seller, price: 1000) }
  let(:headers) { auth_headers_for(buyer) }
  let(:greeting) { "Hi, is this still available?" }

  def start(body = greeting, on: listing)
    post "/api/v1/listings/#{on.id}/conversations", params: { message: body }, headers: headers, as: :json
  end

  # ListingDetail's offer: startConversation(id, default text), then the offer.
  def offer(amount)
    start
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig("conversation", "id")
    post "/api/v1/conversations/#{id}/messages", params: { body: "#{amount}|AFN|1", kind: "offer" }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
  end

  def conversation = Conversation.find_by!(listing: listing, buyer: buyer)

  def shown_messages
    get "/api/v1/conversations/#{conversation.id}/messages", headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body["messages"].reverse.map { |m| [ m["kind"], m["body"] ] }
  end

  describe "Contact seller a second time" do
    it "lands in the same chat, which shows its history, and adds nothing" do
      start("Is it still available?")
      first_id = response.parsed_body.dig("conversation", "id")
      expect { start("Can I see it tomorrow?") }.not_to have_enqueued_job(SendMessagePushJob)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("conversation", "id")).to eq(first_id)
      expect(Conversation.where(listing: listing, buyer: buyer).count).to eq(1)

      get "/api/v1/conversations/#{first_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(shown_messages).to eq([ [ "text", "Is it still available?" ] ])
    end

    # The buyer deleted or archived the chat since: coming back from the listing
    # brings it back to their inbox, so it is where they can find it again.
    %i[delete_for! archive_for!].each do |hide|
      it "a chat the buyer hid (#{hide}) comes back to their inbox, with its history" do
        start("Hello")
        conversation.public_send(hide, buyer)
        start("Hello again")
        get "/api/v1/conversations", headers: headers
        expect(response.parsed_body["conversations"].map { |c| c["id"] }).to include(conversation.id)
        expect(shown_messages).to eq([ [ "text", "Hello" ] ])
      end
    end

    it "the seller's own archive is left alone" do
      start("Hello")
      conversation.archive_for!(seller)
      start("Hello again")
      expect(conversation.reload.seller_archived_at).to be_present
    end
  end

  describe "Make offer a second time" do
    it "both offers land in the one chat, after a single greeting, and both show" do
      offer(800)
      offer(900)
      expect(Conversation.where(listing: listing, buyer: buyer).count).to eq(1)
      expect(shown_messages).to eq([ [ "text", greeting ], [ "offer", "800|AFN|1" ], [ "offer", "900|AFN|1" ] ])
    end
  end

  describe "the daily limit on starting chats (30)" do
    it "coming back to an existing chat does not count as a new start" do
      start
      35.times { start }
      expect(response).to have_http_status(:created)
      start(on: create(:listing, :active))
      expect(response).to have_http_status(:created)
    end

    it "new chats are still limited" do
      30.times { start(on: create(:listing, :active)) }
      start(on: create(:listing, :active))
      expect(response).to have_http_status(:too_many_requests)
    end

    it "coming back is limited like replies (120 an hour)" do
      start
      120.times { start }
      start
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
