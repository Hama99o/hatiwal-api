require "rails_helper"

# Night QA on qa117 (dd, 2026-10-12): an offer's body was never checked, so a
# crafted request stored "abc", "1e999|AFN|5500" or "5|!!|5" as an offer. The
# apps format the 2nd segment with Intl.NumberFormat({ style: "currency" }),
# which THROWS for a code that is not 3 letters: the offer bubble and the inbox
# preview of the seller's Chats tab crashed. Every client sends
# "<amount > 0>|<the listing's currency>|<listed price>", so that is the rule.
RSpec.describe "Offer body format", type: :request do
  let(:seller)       { create(:user) }
  let(:buyer)        { create(:user) }
  let(:listing)      { create(:listing, :active, user: seller, price: 5500, currency: "AFN") }
  let(:conversation) { create(:conversation, listing: listing, buyer: buyer) }

  def send_offer(body, kind: "offer", user: buyer, responds_to_id: nil)
    post "/api/v1/conversations/#{conversation.id}/messages",
         params: { kind: kind, body: body, responds_to_id: responds_to_id }.compact.to_json,
         headers: auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  [
    "abc", "1e999|AFN|5500", "Infinity|AFN|5500", "NaN|AFN|5500", "-5|AFN|5500", "0|AFN|5500",
    "5000|!!|5500", "5000||5500", "5000|afn|5500", "5000|XYZ|5500", "5000", "|AFN|5500", " 5000|AFN|5500"
  ].each do |bad|
    it "refuses an offer with body #{bad.inspect}" do
      expect { send_offer(bad) }.not_to change(Message, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  [ "5000|AFN|5500", "5000.5|AFN|5500.0", "5000|AFN|0", "5000|AFN", "1e+21|AFN|5500" ].each do |good|
    it "accepts a client-shaped offer #{good.inspect}" do
      expect { send_offer(good) }.to change(Message, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end

  it "applies to a counter-offer too" do
    offer = conversation.messages.create!(user: buyer, kind: :offer, body: "5000|AFN|5500")
    send_offer("6000|!!|5500", kind: "offer_counter", user: seller, responds_to_id: offer.id)
    expect(response).to have_http_status(:unprocessable_entity)
    send_offer("6000|AFN|5500", kind: "offer_counter", user: seller, responds_to_id: offer.id)
    expect(response).to have_http_status(:created)
  end

  it "leaves text messages free-form" do
    send_offer("5|!!|5", kind: "text")
    expect(response).to have_http_status(:created)
  end

  it "does not re-validate offers already stored (old rows still load and update)" do
    old = conversation.messages.new(user: buyer, kind: :offer, body: "abc")
    old.save!(validate: false)
    expect(old.reload.update(read_at: Time.current)).to be(true)
  end
end
