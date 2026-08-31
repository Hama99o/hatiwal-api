require "swagger_helper"

# SF-B11 — POST /api/v1/conversations/:conversation_id/messages gains an optional
# `offer_quantity`, so the number two people agreed on survives as data instead of
# only as prose.
#
# The gap, traced: a buyer sets a quantity stepper on a multi-unit listing and
# their opening message reads "3 × AFN 14,000 = AFN 42,000" — but mobile's own
# `firstMessageQuantity.ts` states that "the quantity is never persisted as
# structured data anywhere, only as stated intent in prose", and `OfferSheet.tsx`
# states that "an offer carries no quantity of its own, so nothing downstream
# disambiguates". `Listing#units_for_sale` therefore defaults a batch sale to ONE
# unit: a seller who agreed to sell 3 had to remember and re-type 3, and when
# they didn't, one unit was recorded, stock read 14 where it should have read 12,
# and the listing began lying to the next buyer. An offer is the right carrier
# because it is the moment the two of them agree terms.
RSpec.describe "Api::V1::Messages offer quantity (SF-B11)", type: :request do
  let(:seller)         { create(:user) }
  let(:buyer)          { create(:user) }
  let(:headers)        { auth_headers_for(buyer) }
  let(:seller_headers) { auth_headers_for(seller) }

  # 15 units, none sold.
  let(:batch)        { create(:listing, :active, user: seller, quantity: 15) }
  let(:batch_thread) { create(:conversation, listing: batch, buyer: buyer) }

  let(:single)        { create(:listing, :active, user: seller, quantity: 1) }
  let(:single_thread) { create(:conversation, listing: single, buyer: buyer) }

  def post_message(thread, params, as: nil)
    post "/api/v1/conversations/#{thread.id}/messages",
         params: params, headers: as || headers, as: :json
  end

  def message_body
    JSON.parse(response.body)["message"]
  end

  def messages_in(thread, as: nil)
    get "/api/v1/conversations/#{thread.id}/messages", headers: as || headers, as: :json
    JSON.parse(response.body)["messages"]
  end

  # ── RSwag ───────────────────────────────────────────────────────────────────
  path "/api/v1/conversations/{conversation_id}/messages" do
    parameter name: :conversation_id, in: :path, type: :integer, required: true

    post("send a message in a conversation") do
      tags "Messages"
      description <<~DESC
        Sends a message in a conversation the caller participates in.

        SF-B11 — `offer_quantity` (optional, integer) states how many UNITS an
        offer is for. Only meaningful on `kind: "offer"` / `"offer_counter"`, and
        only on a multi-unit listing (`listing.multi_unit`).

        * **Nullable, and never defaulted to 1.** `null` means the sender said
          nothing about how many, which is what every offer sent before this
          field existed is; clients read `null` as one unit but must not show
          agreed-quantity UI for it. "Absent" and "one" are different facts.
        * **Discarded, not refused**, wherever it cannot mean anything — a
          non-offer kind, a single-item listing, an orphaned thread whose listing
          is gone. A single-item listing is untouched end to end: the response
          carries `offer_quantity: null` and no new failure mode exists for it.
        * **Refused when it exceeds `listing.available_units`** at the moment it
          is sent: 422 with `code: "offer_quantity_above_available_units"`. Never
          silently clamped — an offer is a proposal, and rewriting "I'll take 20"
          into "I'll take 12" would hand both sides a number neither chose.
        * A non-positive or fractional value is refused as an ordinary 422 with
          no `code` (it is a client bug, not something the sender can act on).

        **Reading the agreed quantity off an accepted offer:** an accept is a
        separate message (`kind: "offer_accepted"`) whose `responds_to_id` points
        at the offer it answers. Read `offer_amount` + `offer_quantity` off that
        offer, then pass the quantity through to `PUT /api/v1/my/listings/:id/sold`
        as its existing `quantity` param — no change to that endpoint.
      DESC
      consumes "application/json"
      produces "application/json"

      parameter name: :message, in: :body, required: true, schema: {
        type: :object,
        properties: {
          body: { type: :string, description: 'For offers: "amount|currency|listedPrice"' },
          kind: { type: :string, enum: Message::USER_SENDABLE_KINDS },
          responds_to_id: { type: :integer, nullable: true,
                            description: "Message being answered — must be in the SAME conversation" },
          offer_quantity: { type: :integer, nullable: true,
                            description: "SF-B11 — units this offer is for; null means unspecified" }
        },
        required: [ "body" ]
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      let(:conversation_id) { batch_thread.id }
      let(:message)         { { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 } }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "201", "offer for 3 of the 15 units" do
        run_test! do |response|
          body = JSON.parse(response.body)["message"]
          expect(body["kind"]).to eq("offer")
          expect(body["offer_amount"]).to eq(12_000.0)
          expect(body["offer_quantity"]).to eq(3)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end

      response "422", "offer for more units than the listing has left" do
        let(:message) { { body: "12000|AFN|14000", kind: "offer", offer_quantity: 20 } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["code"]).to eq(Message::OFFER_QUANTITY_ABOVE_AVAILABLE_CODE)
          expect(body["errors"].join).to include("15 units still available")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  # ── An offer with a quantity round-trips and is readable off the accept ──────
  describe "a quantity on a multi-unit listing" do
    it "round-trips through create and index" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })

      expect(response).to have_http_status(:created)
      expect(message_body["offer_quantity"]).to eq(3)

      listed = messages_in(batch_thread).first
      expect(listed["offer_quantity"]).to eq(3)
      # The pre-existing parsed fields are untouched.
      expect(listed["offer_amount"]).to eq(12_000.0)
      expect(listed["offer_currency"]).to eq("AFN")
    end

    it "is readable off the ACCEPTED offer by following responds_to_id" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      offer_id = message_body["id"]

      # The seller accepts. The accept is its own message pointing back at the offer.
      post_message(batch_thread,
                   { body: "12000|AFN|14000", kind: "offer_accepted", responds_to_id: offer_id },
                   as: seller_headers)
      expect(response).to have_http_status(:created)

      # How a client reads the agreed terms: find the accept, follow its
      # responds_to_id, read the offer's amount and quantity.
      all      = messages_in(batch_thread, as: seller_headers)
      accepted = all.find { |m| m["kind"] == "offer_accepted" }
      agreed   = all.find { |m| m["id"] == accepted["responds_to_id"] }

      expect(agreed["offer_quantity"]).to eq(3)
      expect(agreed["offer_amount"]).to eq(12_000.0)
    end

    it "survives a counter — a counter can restate how many" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      offer_id = message_body["id"]

      post_message(batch_thread,
                   { body: "13000|AFN|14000", kind: "offer_counter",
                     responds_to_id: offer_id, offer_quantity: 2 },
                   as: seller_headers)

      expect(response).to have_http_status(:created)
      expect(message_body["kind"]).to eq("offer_counter")
      expect(message_body["offer_quantity"]).to eq(2)
      expect(message_body["responds_to_id"]).to eq(offer_id)
    end

    # THE GAP, CLOSED. The seller no longer has to remember "3": the accepted
    # offer carries it, and mark-sold's existing `quantity` param takes it.
    it "lets mark-sold record the agreed units instead of defaulting to one" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      agreed_units = message_body["offer_quantity"]

      put "/api/v1/my/listings/#{batch.id}/sold",
          params: { buyer_id: buyer.id, final_price: 12_000, quantity: agreed_units },
          headers: seller_headers, as: :json

      expect(response).to have_http_status(:ok)
      listing = JSON.parse(response.body)["listing"]
      expect(listing["available_units"]).to eq(12)
      expect(listing["status"]).to eq("active")
      expect(batch.reload.sold_units).to eq(3)
    end

    it "still defaults to one unit when the offer stated no quantity (unchanged behaviour)" do
      batch_thread # the buyer picker only offers conversation participants

      put "/api/v1/my/listings/#{batch.id}/sold",
          params: { buyer_id: buyer.id }, headers: seller_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(batch.reload.sold_units).to eq(1)
    end

    # A stored offer quantity is a PROPOSAL, and like the price in the same offer
    # it can go stale — the seller may edit the listing's `quantity` down
    # afterwards (SF-B6 allows it above `sold_units`/`held_units`). It must never
    # be able to oversell: `Listing#units_for_sale` clamps at mark-sold time and
    # the `listings_sold_units_within_quantity` CHECK is the backstop.
    it "cannot oversell when the seller later shrinks the listing" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 5 })
      agreed_units = message_body["offer_quantity"]

      put "/api/v1/my/listings/#{batch.id}",
          params: { listing: { quantity: 3 } }, headers: seller_headers, as: :json
      expect(response).to have_http_status(:ok)

      put "/api/v1/my/listings/#{batch.id}/sold",
          params: { buyer_id: buyer.id, quantity: agreed_units }, headers: seller_headers, as: :json

      expect(response).to have_http_status(:ok)
      batch.reload
      expect(batch.sold_units).to eq(3)
      expect(batch.available_units).to eq(0)
      expect(batch.available_units).to be >= batch.held_units
    end

    it "suppresses the quantity on a retracted offer, like every other offer field" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      offer_id = message_body["id"]

      delete "/api/v1/conversations/#{batch_thread.id}/messages/#{offer_id}",
             headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(message_body["deleted"]).to be(true)
      expect(message_body["offer_quantity"]).to be_nil
      expect(message_body["offer_amount"]).to be_nil
    end
  end

  # ── The regression guard for every offer that already exists ────────────────
  describe "an offer with NO quantity" do
    it "behaves exactly as before and reports offer_quantity: null" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer" })

      expect(response).to have_http_status(:created)
      body = message_body
      expect(body["offer_quantity"]).to be_nil
      expect(body["offer_amount"]).to eq(12_000.0)
      expect(body["offer_currency"]).to eq("AFN")
    end

    it "reads back null for an offer written before the column existed" do
      legacy = create(:message, :offer, conversation: batch_thread, user: buyer)

      listed = messages_in(batch_thread).find { |m| m["id"] == legacy.id }
      expect(listed["offer_quantity"]).to be_nil
      expect(listed["offer_amount"]).to eq(8000.0)
    end

    it "leaves a plain text message with offer_quantity: null" do
      post_message(batch_thread, { body: "Is this still available?" })

      expect(response).to have_http_status(:created)
      expect(message_body["offer_quantity"]).to be_nil
    end
  end

  # ── Over-available is refused, not clamped ──────────────────────────────────
  describe "a quantity above available_units" do
    it "422s with the machine-readable code and persists nothing" do
      expect {
        post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 20 })
      }.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["code"]).to eq("offer_quantity_above_available_units")
      expect(body["errors"].join).to eq(
        "Offer quantity cannot be more than the 15 units still available. Set it to 15 or fewer."
      )
    end

    it "measures against what is LEFT, not the listing total" do
      batch.update!(sold_units: 12) # 3 left of 15

      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 4 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"].join).to include("the 3 units still available")
    end

    it "accepts the boundary exactly" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 15 })

      expect(response).to have_http_status(:created)
      expect(message_body["offer_quantity"]).to eq(15)
    end

    it "422s a non-positive quantity with NO code" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 0 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).not_to have_key("code")
    end
  end

  # ── A single-item listing is untouched on every path ────────────────────────
  describe "a single-item listing" do
    it "reports offer_quantity: null on an offer that states one" do
      post_message(single_thread, { body: "9000|AFN|10000", kind: "offer", offer_quantity: 1 })

      expect(response).to have_http_status(:created)
      expect(message_body["offer_quantity"]).to be_nil
    end

    it "ignores an over-available quantity instead of inventing a 422" do
      post_message(single_thread, { body: "9000|AFN|10000", kind: "offer", offer_quantity: 9 })

      expect(response).to have_http_status(:created)
      expect(message_body["offer_quantity"]).to be_nil
      expect(JSON.parse(response.body)).not_to have_key("code")
    end

    it "carries offer_quantity: null on every message kind in the thread" do
      post_message(single_thread, { body: "9000|AFN|10000", kind: "offer", offer_quantity: 1 })
      offer_id = message_body["id"]
      post_message(single_thread,
                   { body: "9500|AFN|10000", kind: "offer_counter", responds_to_id: offer_id, offer_quantity: 1 },
                   as: seller_headers)
      counter_id = message_body["id"]
      post_message(single_thread, { body: "9500|AFN|10000", kind: "offer_accepted", responds_to_id: counter_id })
      post_message(single_thread, { body: "See you at 5" })

      quantities = messages_in(single_thread).map { |m| m["offer_quantity"] }
      expect(quantities).to all(be_nil)
      expect(quantities.length).to eq(4)
    end

    it "still sells its one unit with no quantity anywhere in the flow" do
      post_message(single_thread, { body: "9000|AFN|10000", kind: "offer" })
      offer_id = message_body["id"]
      post_message(single_thread, { body: "9000|AFN|10000", kind: "offer_accepted", responds_to_id: offer_id },
                   as: seller_headers)

      put "/api/v1/my/listings/#{single.id}/sold",
          params: { buyer_id: buyer.id, final_price: 9000 }, headers: seller_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["status"]).to eq("sold")
      expect(single.reload.sold_units).to eq(1)
    end
  end

  # ── The accept/decline flow and the responds_to_id guard are untouched ──────
  describe "the offer accept flow (TASK-K071/K072 territory)" do
    it "still accepts an offer that carries a quantity" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      offer_id = message_body["id"]

      post_message(batch_thread,
                   { body: "12000|AFN|14000", kind: "offer_accepted", responds_to_id: offer_id },
                   as: seller_headers)

      expect(response).to have_http_status(:created)
      expect(message_body["kind"]).to eq("offer_accepted")
      expect(message_body["responds_to_id"]).to eq(offer_id)
      # An accept is not an offer, so it carries no quantity of its own — the
      # agreed number is read off the offer it points at.
      expect(message_body["offer_quantity"]).to be_nil
    end

    it "still declines an offer that carries a quantity" do
      post_message(batch_thread, { body: "12000|AFN|14000", kind: "offer", offer_quantity: 3 })
      offer_id = message_body["id"]

      post_message(batch_thread,
                   { body: "12000|AFN|14000", kind: "offer_declined", responds_to_id: offer_id },
                   as: seller_headers)

      expect(response).to have_http_status(:created)
      expect(message_body["kind"]).to eq("offer_declined")
    end

    it "still refuses to accept an offer from a DIFFERENT conversation" do
      other_listing = create(:listing, :active, user: seller, quantity: 15)
      other_thread  = create(:conversation, listing: other_listing, buyer: buyer)
      foreign_offer = create(:message, :offer, conversation: other_thread, user: buyer, offer_quantity: 3)

      post_message(batch_thread,
                   { body: "12000|AFN|14000", kind: "offer_accepted", responds_to_id: foreign_offer.id },
                   as: seller_headers)

      expect(response).to have_http_status(:unprocessable_content)
      # The 422 shape for this failure is unchanged — no `code` key.
      expect(JSON.parse(response.body)).not_to have_key("code")
      expect(Message.where(responds_to_id: foreign_offer.id, conversation: batch_thread)).to be_empty
    end

    it "still refuses a counter that carries a quantity but points at another conversation" do
      other_listing = create(:listing, :active, user: seller, quantity: 15)
      other_thread  = create(:conversation, listing: other_listing, buyer: buyer)
      foreign_offer = create(:message, :offer, conversation: other_thread, user: buyer)

      post_message(batch_thread,
                   { body: "13000|AFN|14000", kind: "offer_counter",
                     responds_to_id: foreign_offer.id, offer_quantity: 2 },
                   as: seller_headers)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Message.where(conversation: batch_thread, kind: :offer_counter)).to be_empty
    end
  end
end
