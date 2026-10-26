require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1) — messages.client_uuid.
#
# The phone names a message before it sends it. The answer carries the name
# back (REST and the cable), so the sender's optimistic bubble and their other
# devices swap the pending bubble for the real one instead of showing it twice.
RSpec.describe "Message client_uuid", type: :request do
  let(:buyer)        { create(:user) }
  let(:listing)      { create(:listing, :active) }
  let(:conversation) { create(:conversation, listing: listing, buyer: buyer) }
  let(:uuid)         { SecureRandom.uuid }

  def sent = JSON.parse(response.body)["message"]

  def send_message(body: "Is it still available?", client_uuid: uuid, chat: conversation)
    post "/api/v1/conversations/#{chat.id}/messages",
         params: { body: body, client_uuid: client_uuid }.compact, headers: auth_headers_for(buyer), as: :json
  end

  it "is stored and returned" do
    expect { send_message }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(sent["client_uuid"]).to eq(uuid)
  end

  it "a resend of a message already sent (its answer lost, no Idempotency-Key) returns it: 200, still one message" do
    send_message
    first_id = sent["id"]
    expect(first_id).to be_present

    expect { send_message }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
    expect(sent["id"]).to eq(first_id)
  end

  it "is null from an app that does not send one (every 1.1.x app), and two such messages are two" do
    expect do
      2.times { send_message(client_uuid: nil) }
    end.to change(Message, :count).by(2)
    expect(sent).to include("client_uuid" => nil)
  end

  it "the same client_uuid in ANOTHER chat → 422 client_uuid_taken, nothing written" do
    send_message
    other = create(:conversation, listing: create(:listing, :active), buyer: buyer)

    expect { send_message(chat: other) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["code"]).to eq("client_uuid_taken")
  end

  it "a malformed client_uuid → 422" do
    expect { send_message(client_uuid: "x y") }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rides the cable broadcast, so the sender's other devices can match it" do
    send_message
    message = Message.find(sent["id"])

    expect { BroadcastMessageJob.perform_now(message.id) }
      .to have_broadcasted_to("conversation_#{conversation.id}").with { |d| expect(d[:message][:client_uuid]).to eq(uuid) }
  end
end
