require "swagger_helper"

# SF-B6 — PUT /api/v1/my/listings/:id with a changed `quantity`.
#
# The owner's report, end to end: 15 of 15 sold, seller edits the quantity to 20,
# and the five new units were stranded — the listing stayed `sold`, so it was out
# of the buyer feed and the seller could not mark any of them sold either. The
# opposite edit (quantity below what is already sold) hit the DB CHECK constraint
# and came back as a 500 with an empty body, which the mobile app can only render
# as its generic "server error" — the seller was told nothing at all.
#
# SF-B8 adds the sibling floor to the same endpoint: `quantity` may not fall
# below the units ON HOLD for a buyer either. Before it, a 15-unit listing with 10
# held accepted an edit down to `quantity: 2`, and the buyer-facing held pill
# (SF-M4) rendered "2 available · 10 held" — a wrong number, on a buyer's screen.
RSpec.describe "Api::V1::My::Listings quantity edits (SF-B6, SF-B8)", type: :request do
  let(:seller)  { create(:user) }
  let(:buyer)   { create(:user) }
  let(:headers) { auth_headers_for(seller) }

  def sold_out(total:, expires_at: nil)
    create(:listing, :sold, user: seller, quantity: total, sold_units: total, expires_at: expires_at)
  end

  # A live listing with `held` units on hold for `buyer`. The buyer picker only
  # offers conversation participants and Transaction enforces it, so the
  # conversation is part of the setup, not decoration.
  def with_hold(total:, held:, sold: 0)
    listing = create(:listing, :active, user: seller, quantity: total, sold_units: sold)
    create(:conversation, listing: listing, buyer: buyer)
    listing.reserve_with_buyer!(buyer_id: buyer.id, quantity: held)
    listing.reload
  end

  def put_quantity(listing, quantity)
    put "/api/v1/my/listings/#{listing.id}",
        params: { listing: { quantity: quantity } }, headers: headers, as: :json
  end

  # ── RSwag ───────────────────────────────────────────────────────────────────
  path "/api/v1/my/listings/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true

    put("update one of the caller's own listings") do
      tags "Listings"
      description <<~DESC
        Edits a listing the caller owns. Photos are appended (never replaced) and
        removed by signed id via `removed_image_ids`.

        SF-B6 — changing `quantity` reconciles the listing's own status:

        * raising it above `sold_units` re-opens a `sold` listing as `active`,
          clears `sold_at`, and refreshes `expires_at` when the 30-day clock had
          already run out (so it comes back into the feed, not into the seller's
          Expired tab);
        * lowering it onto `sold_units` retires a live listing as `sold`;
        * lowering it BELOW `sold_units` is refused with 422 +
          `code: "quantity_below_sold_units"`. The seller's way out is to undo a
          sale first (`DELETE /api/v1/my/transactions/:id`, SF-B4).

        SF-B8 — the same endpoint enforces a second floor: lowering `quantity`
        below the units currently ON HOLD for a buyer is refused with 422 +
        `code: "quantity_below_held_units"`. The hold is never silently shrunk.
        The seller's way out is to release the hold
        (`PUT /api/v1/my/listings/:id/activate`) or set the quantity to at least
        the held count.

        The two floors report EXCLUSIVELY — whichever is higher raises the error,
        so `code` is one value and the minimum named in the message is always the
        minimum that actually works.
      DESC
      consumes "application/json"
      produces "application/json"

      parameter name: :listing_update, in: :body, required: true, schema: {
        type: :object,
        properties: {
          listing: {
            type: :object,
            properties: {
              title:    { type: :string },
              price:    { type: :number },
              quantity: { type: :integer, description: "Total units; may not be below sold_units" }
            }
          }
        }
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      let(:record)         { sold_out(total: 15, expires_at: 3.days.ago) }
      let(:id)             { record.id }
      let(:listing_update) { { listing: { quantity: 20 } } }

      response "401", "unauthorized" do
        let(:"access-token") { nil }
        run_test! { expect(response).to have_http_status(:unauthorized) }
      end

      response "200", "quantity raised — the sold-out listing re-opens with its stock" do
        run_test! do |response|
          body = JSON.parse(response.body)["listing"]
          expect(body["status"]).to eq("active")
          expect(body["available_units"]).to eq(5)
          expect(body["expired"]).to be(false)
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end

      response "422", "quantity below the units already sold" do
        let(:listing_update) { { listing: { quantity: 10 } } }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["code"]).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
          expect(body["errors"].join).to include("already sold")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => { example: JSON.parse(response.body, symbolize_names: true) }
          }
        end
      end
    end
  end

  # ── Functional specs ────────────────────────────────────────────────────────
  describe "raising the quantity of a sold-out listing" do
    it "re-opens it, refreshes the expiry, and puts it back in the feed" do
      listing = sold_out(total: 15, expires_at: 3.days.ago)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 20 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["listing"]
      expect(body["status"]).to eq("active")
      expect(body["available_units"]).to eq(5)
      expect(body["sold_at"]).to be_nil
      expect(body["expired"]).to be(false)

      listing.reload
      expect(Listing.browsable).to include(listing)
      expect(ListingPolicy.new(seller, listing).sold?).to be(true)
    end

    it "lets the seller actually sell the recovered units" do
      listing = sold_out(total: 15, expires_at: 3.days.ago)
      create(:conversation, listing: listing, buyer: buyer)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 20 } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      put "/api/v1/my/listings/#{listing.id}/sold",
          params: { buyer_id: buyer.id, quantity: 2 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.sold_units).to eq(17)
      expect(listing.status).to eq("active")
    end

    it "shows up in the seller's Active tab, not the Expired one" do
      listing = sold_out(total: 15, expires_at: 3.days.ago)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 20 } }, headers: headers, as: :json

      get "/api/v1/my/listings", params: { status: "active" }, headers: headers, as: :json
      expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).to include(listing.id)

      get "/api/v1/my/listings", params: { status: "expired" }, headers: headers, as: :json
      expect(JSON.parse(response.body)["listings"].map { |l| l["id"] }).not_to include(listing.id)
    end
  end

  describe "lowering the quantity" do
    it "retires a live listing when the quantity meets the units already sold" do
      listing = create(:listing, :active, user: seller, quantity: 20, sold_units: 15)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 15 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("listing", "status")).to eq("sold")
      expect(listing.reload.status).to eq("sold")
    end

    it "is a 422 with a field error — never a 500 with an empty body" do
      listing = sold_out(total: 15)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 10 } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["code"]).to eq("quantity_below_sold_units")
      expect(body["errors"]).to include(
        "Quantity cannot be less than the 15 units already sold. " \
        "Set it to 15 or more, or undo a sale first."
      )
      expect(listing.reload.quantity).to eq(15)
    end

    it "goes through once the seller undoes the sale first (SF-B4's way out)" do
      listing = create(:listing, :active, user: seller, quantity: 15, price: 1000)
      create(:conversation, listing: listing, buyer: buyer)
      txn = listing.sold_with_buyer!(buyer_id: buyer.id, quantity: 15)
      listing.record_units_sold!(15)
      listing.sold!

      delete "/api/v1/my/transactions/#{txn.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { quantity: 10 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(10)
      expect(listing.sold_units).to eq(0)
    end
  end

  describe "edits that must change nothing" do
    it "leaves a sold listing sold when only the title changes" do
      listing = sold_out(total: 15)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "Same bags, better photo" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("listing", "status")).to eq("sold")
      expect(listing.reload.status).to eq("sold")
    end

    it "leaves a single-item listing alone" do
      listing = create(:listing, :active, user: seller, quantity: 1)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { price: 4200 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.status).to eq("active")
      expect(listing.quantity).to eq(1)
      expect(listing.available_units).to eq(1)
    end
  end

  # ── SF-B8: the open-hold floor ──────────────────────────────────────────────
  describe "lowering the quantity below an open hold (SF-B8)" do
    it "is a 422 with a :quantity field error and the held-units code" do
      listing = with_hold(total: 15, held: 10)

      put_quantity(listing, 2)

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["code"]).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)
      expect(body["code"]).to eq("quantity_below_held_units")
      expect(body["errors"]).to include(
        "Quantity cannot be less than the 10 units on hold for a buyer. " \
        "Release the hold first, or set it to 10 or more."
      )
      # REFUSED, not silently shrunk: both the stock and the buyer's hold survive.
      listing.reload
      expect(listing.quantity).to eq(15)
      expect(listing.held_units).to eq(10)
      expect(listing.open_transaction).to be_present
    end

    it "never renders a nonsense pill: available_units stays >= held_units" do
      listing = with_hold(total: 15, held: 10)

      put_quantity(listing, 2)

      expect(response).to have_http_status(:unprocessable_entity)
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer), as: :json
      body = JSON.parse(response.body)["listing"]
      expect(body["held_units"]).to eq(10)
      expect(body["available_units"]).to be >= body["held_units"]
    end

    it "allows an edit down to EXACTLY the held count" do
      listing = with_hold(total: 15, held: 10)

      put_quantity(listing, 10)

      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.quantity).to eq(10)
      expect(listing.held_units).to eq(10)
    end

    it "allows an edit that raises the quantity while units are held" do
      listing = with_hold(total: 15, held: 10)

      put_quantity(listing, 30)

      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(30)
    end

    it "leaves a listing with no open hold completely unaffected" do
      listing = create(:listing, :active, user: seller, quantity: 15)

      put_quantity(listing, 2)

      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(2)
    end

    it "falls back to the sold-units floor once the hold is gone" do
      listing = with_hold(total: 15, held: 10)
      listing.cancel_open_transaction!
      listing.record_units_sold!(10)

      # 10 sold, nothing held: the sold-units floor applies, the hold floor does
      # not, and `quantity: 10` is now legal where it was refused a moment ago.
      put_quantity(listing, 10)
      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(10)

      put_quantity(listing, 9)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
    end

    it "leaves a single-item listing with a hold alone" do
      listing = create(:listing, :active, user: seller, quantity: 1)
      create(:conversation, listing: listing, buyer: buyer)
      listing.reserve_with_buyer!(buyer_id: buyer.id)
      listing.reserved!

      # A one-unit hold can never breach the floor: `quantity` is already
      # validated greater_than 0, so the smallest legal value equals the hold.
      put_quantity(listing.reload, 1)
      expect(response).to have_http_status(:ok)

      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { price: 4200 } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      listing.reload
      expect(listing.quantity).to eq(1)
      expect(listing.held_units).to eq(1)
      expect(listing.price).to eq(4200)
    end

    it "never strands a row that is ALREADY below its hold" do
      listing = with_hold(total: 15, held: 10)
      # Exactly the row this bug has been creating since SF-B2 shipped holds with
      # a quantity — written the way it was written then: no validation.
      listing.update_column(:quantity, 2)

      # An unrelated edit still goes through (the floor is only consulted when
      # `quantity` itself changes)...
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "Same bags, new photo" } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      # ...and so does renewing it, which SF-B7 would otherwise have to answer as
      # a 422 forever.
      put "/api/v1/my/listings/#{listing.id}/renew", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      # Lowering it further is still refused, and raising it to the held count is
      # the repair.
      put_quantity(listing, 1)
      expect(response).to have_http_status(:unprocessable_entity)

      put_quantity(listing, 10)
      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(10)
    end
  end

  describe "the way out of an open-hold refusal (SF-B8, end to end)" do
    it "releases the hold via PUT activate, then the same down-edit succeeds" do
      listing = with_hold(total: 15, held: 10)

      put_quantity(listing, 2)
      expect(response).to have_http_status(:unprocessable_entity)

      # A BATCH keeps status `active` while units are held (SF-B2), so this is the
      # path ListingPolicy#activate? was widened for in SF-B8 — without it the
      # refusal names a way out that 403s.
      put "/api/v1/my/listings/#{listing.id}/activate", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("listing", "held_units")).to eq(0)

      put_quantity(listing, 2)
      expect(response).to have_http_status(:ok)
      listing.reload
      expect(listing.quantity).to eq(2)
      expect(listing.held_units).to eq(0)
      expect(listing.open_transaction).to be_nil
    end
  end

  describe "both quantity floors at once (SF-B6 x SF-B8)" do
    it "reports ONE error naming the HELD count when the hold is the higher floor" do
      listing = with_hold(total: 20, held: 10, sold: 8)

      put_quantity(listing, 5)

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"].size).to eq(1)
      expect(body["code"]).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)
      expect(body["errors"].first).to include("10 units on hold")
      expect(body["errors"].first).not_to include("already sold")
    end

    it "the minimum it names actually works — no contradictory pair" do
      listing = with_hold(total: 20, held: 10, sold: 8)

      # Obeying the LOWER floor alone (the 8 already sold) must not be offered as
      # a fix, because it is still refused.
      put_quantity(listing, 8)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq(Listing::QUANTITY_BELOW_HELD_UNITS_CODE)

      # The number the error DID name goes through.
      put_quantity(listing, 10)
      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(10)
    end

    it "reports ONE error naming the SOLD count when that is the higher floor" do
      listing = with_hold(total: 20, held: 5, sold: 12)

      put_quantity(listing, 6)

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"].size).to eq(1)
      expect(body["code"]).to eq(Listing::QUANTITY_BELOW_SOLD_UNITS_CODE)
      expect(body["errors"].first).to include("12 units already sold")
      expect(body["errors"].first).not_to include("on hold")

      # And that minimum works too — it clears the hold floor as well (12 >= 5).
      put_quantity(listing, 12)
      expect(response).to have_http_status(:ok)
      expect(listing.reload.quantity).to eq(12)
    end
  end
end
