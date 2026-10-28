require "swagger_helper"

# OFFLINE (1.2.0) — RSwag for the writes the app's outbox queues that had no documentation, and
# for the contract answers every queued write can get: the Idempotency-Key replay, 409 in
# progress, 422 reused / invalid, 429 with Retry-After, `already: true` for a target state, 403
# `listing_not_managed`, and a review's base → 409. The behaviour itself is covered by the
# request specs (idempotency_spec, listing_target_state_spec, not_managed_spec, rate_limits_spec,
# reviews_spec); these examples are the documentation's.
RSpec.describe "OFFLINE contract (RSwag)", type: :request do
  let(:me)      { create(:user) }
  let(:headers) { auth_headers_for(me) }
  let(:"access-token") { headers["access-token"] }
  let(:client)         { headers["client"] }
  let(:uid)            { headers["uid"] }
  let(:category) { create(:category) }

  def self.auth_headers
    parameter name: :"access-token", in: :header, type: :string, required: false
    parameter name: :client,         in: :header, type: :string, required: false
    parameter name: :uid,            in: :header, type: :string, required: false
  end

  def json = JSON.parse(response.body)

  # ── Creating a listing: the Idempotency-Key contract, shown on the write the outbox queues most ──
  path "/api/v1/my/listings" do
    post("create a listing (Me, or a shop the seller is in)") do
      tags "Listings"
      consumes "application/json"
      produces "application/json"
      description "`shop_id` (OFFLINE §10.6): the identity the listing is made under, as the app queued it " \
                  "(absent: the server's current \"selling as\"). `listing.image_order` (phase 0): the photos' order " \
                  "as tokens. Limited to 30 a day per seller: 429 with `Retry-After` (seconds)."
      auth_headers
      idempotency_key_header
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          shop_id: { type: :string, nullable: true, description: "OFFLINE §10.6 — `me` or a shop id" },
          listing: {
            type: :object,
            properties: {
              title: { type: :string }, price: { type: :number }, currency: { type: :string },
              category_id: { type: :integer }, status: { type: :string, enum: %w[draft active] },
              image_order: { type: :array, items: { type: :string },
                             description: "Phase 0 — the photos' order: `new:<n>` for the n-th uploaded file" }
            }
          }
        }
      }
      let(:body) { { listing: { title: "Bike", price: 3000, currency: "AFN", category_id: category.id } } }
      let(:key) { SecureRandom.uuid }

      response "201", "created" do
        let(:"Idempotency-Key") { key }
        run_test! { expect(json.dig("listing", "title")).to eq("Bike") }
      end

      response "201", "a retry with the same key: the FIRST answer replayed (Idempotent-Replayed: true), no second listing" do
        header "Idempotent-Replayed", schema: { type: :string }, description: "\"true\" on a replayed answer"
        let(:"Idempotency-Key") { key }
        before { post "/api/v1/my/listings", params: body, headers: headers.merge("Idempotency-Key" => key), as: :json }
        run_test! do
          expect(response.headers["Idempotent-Replayed"]).to eq("true")
          expect(Listing.where(title: "Bike").count).to eq(1)
        end
      end

      response "409", "the first request with this key is still running: retry later" do
        let(:"Idempotency-Key") { key }
        before do
          post "/api/v1/my/listings", params: body, headers: headers.merge("Idempotency-Key" => key), as: :json
          IdempotencyKey.find_by!(user: me, key: key).update!(status: :in_progress, response_code: nil, response_body: nil)
        end
        run_test! { expect(json["code"]).to eq("idempotency_in_progress") }
      end

      response "422", "the same key with a DIFFERENT request" do
        let(:"Idempotency-Key") { key }
        before do
          post "/api/v1/my/listings", params: body.deep_merge(listing: { title: "Another bike" }),
                                      headers: headers.merge("Idempotency-Key" => key), as: :json
        end
        run_test! { expect(json["code"]).to eq("idempotency_key_reused") }
      end

      response "429", "over the daily limit: Retry-After says when (never a 429 replayed under a key)" do
        header "Retry-After", schema: { type: :integer }, description: "seconds — the limit window's length"
        before { 30.times { post "/api/v1/my/listings", params: body, headers: headers, as: :json } }
        run_test! { expect(response.headers["Retry-After"]).to eq(1.day.to_i.to_s) }
      end
    end
  end

  # ── Deleting a listing: 204, or 403 for a former shop member (a queued delete must be told) ──
  path "/api/v1/my/listings/{id}" do
    delete("delete (soft-remove) a listing") do
      tags "Listings"
      produces "application/json"
      description "Already removed (another device, a lost answer's retry) → 204 as well. A listing of a shop the " \
                  "caller has left or was removed from → 403 `code: \"listing_not_managed\"` (OFFLINE, QA audit A5): " \
                  "never a 404 a queue would take as done."
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer

      response "204", "removed" do
        let(:id) { create(:listing, :active, user: me).id }
        run_test!
      end

      response "403", "the caller no longer manages it" do
        let(:owner) { create(:user) }
        let(:shop) { create(:shop, owner: owner) }
        let(:id) do
          shop.shop_members.create!(user: me, role: :staff)
          listing = create(:listing, :active, user: owner, shop: shop)
          shop.remove_team_member!(me, by: owner)
          listing.id
        end
        run_test! { expect(json["code"]).to eq("listing_not_managed") }
      end
    end
  end

  # ── Status changes are TARGET states (§10.3): a listing already there is a success, `already: true` ──
  { "publish" => [ "publish a draft (it goes live)", :draft, :active ],
    "sold" => [ "mark sold (one tap, no hold needed)", :active, :sold ] }.each do |action, (summary, from, already)|
    path "/api/v1/my/listings/{id}/#{action}" do
      put(summary) do
        tags "Listings"
        consumes "application/json"
        produces "application/json"
        description "OFFLINE §10.3 — a target state: a listing ALREADY #{already} (the web, a teammate, this " \
                    "request's lost first answer) → 200 with `already: true`, nothing changed. A removed listing is refused."
        auth_headers
        idempotency_key_header
        parameter name: :id, in: :path, type: :integer

        response "200", "done" do
          let(:id) { create(:listing, from, :with_image, user: me).id }
          run_test! { expect(json["already"]).to be_nil }
        end

        response "200", "already in that state: `already: true`" do
          let(:id) do
            listing = create(:listing, :active, :with_image, user: me)
            put "/api/v1/my/listings/#{listing.id}/sold", headers: headers, as: :json if already == :sold
            listing.id
          end
          run_test! { expect(json["already"]).to be(true) }
        end
      end
    end
  end

  path "/api/v1/my/listings/relaunch_expired" do
    post("relaunch every expired listing (Me, or a shop)") do
      tags "Listings"
      produces "application/json"
      auth_headers
      idempotency_key_header

      response "200", "how many went live again" do
        run_test! { expect(json).to include("renewed", "failed") }
      end
    end
  end

  # ── The buyer side and the social writes the outbox queues ──
  path "/api/v1/listings/{id}/hide" do
    post("hide a listing from the caller's feed") do
      tags "Listings"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer
      let(:id) { create(:listing, :active).id }

      response "200", "hidden" do
        run_test! { expect(json["hidden"]).to be(true) }
      end
    end
  end

  path "/api/v1/listings/{id}/unhide" do
    delete("show a hidden listing again") do
      tags "Listings"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer
      let(:id) { create(:listing, :active).id }

      response "200", "shown again" do
        run_test! { expect(json["hidden"]).to be(false) }
      end
    end
  end

  path "/api/v1/listings/{listing_id}/conversations" do
    post("message the seller: starts (or finds) the conversation with a first message") do
      tags "Conversations"
      consumes "application/json"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :listing_id, in: :path, type: :integer
      parameter name: :body, in: :body, schema: { type: :object, properties: { message: { type: :string } } }
      let(:listing_id) { create(:listing, :active).id }
      let(:body) { { message: "Is it still for sale?" } }

      response "201", "the conversation" do
        run_test! { expect(json.dig("conversation", "id")).to be_present }
      end
    end
  end

  path "/api/v1/conversations/{id}" do
    delete("delete a conversation for the caller") do
      tags "Conversations"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer

      response "204", "deleted for the caller" do
        let(:id) { Conversations::StartService.new(buyer: me, listing: create(:listing, :active), message_body: "Hi").call.id }
        run_test!
      end
    end
  end

  path "/api/v1/conversations/{conversation_id}/messages/{id}" do
    delete("delete the caller's own message") do
      tags "Messages"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :conversation_id, in: :path, type: :integer
      parameter name: :id, in: :path, type: :integer
      let(:conversation) { Conversations::StartService.new(buyer: me, listing: create(:listing, :active), message_body: "Hi").call }
      let(:conversation_id) { conversation.id }
      let(:id) { conversation.messages.where(user: me).first.id }

      response "200", "the message, now deleted" do
        run_test!
      end
    end
  end

  path "/api/v1/users/{user_id}/block" do
    post("block a person") do
      tags "Blocks"
      auth_headers
      idempotency_key_header
      parameter name: :user_id, in: :path, type: :integer
      let(:user_id) { create(:user).id }

      response "204", "blocked" do
        run_test!
      end
    end

    delete("unblock a person") do
      tags "Blocks"
      auth_headers
      idempotency_key_header
      parameter name: :user_id, in: :path, type: :integer
      let(:user_id) { create(:user).tap { |u| me.blocked_users << u }.id }

      response "204", "unblocked (a 204 is replayed as a 204 under its key)" do
        run_test!
      end
    end
  end

  path "/api/v1/shops/{shop_id}/block" do
    post("block a shop (its owner underneath)") do
      tags "Blocks"
      auth_headers
      idempotency_key_header
      parameter name: :shop_id, in: :path, type: :integer
      let(:shop_id) { create(:shop).id }

      response "204", "blocked" do
        run_test!
      end
    end

    delete("unblock a shop") do
      tags "Blocks"
      auth_headers
      idempotency_key_header
      parameter name: :shop_id, in: :path, type: :integer
      let(:shop_id) { create(:shop).id }

      response "204", "unblocked" do
        run_test!
      end
    end
  end

  path "/api/v1/users/saved_searches/{id}" do
    delete("delete a saved search") do
      tags "Saved searches"
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer
      let(:id) { create(:saved_search, user: me).id }

      response "204", "deleted" do
        run_test!
      end
    end
  end

  path "/api/v1/users/saved_searches/{id}/mark_seen" do
    put("mark a saved search's new results as seen") do
      tags "Saved searches"
      produces "application/json"
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer
      let(:id) { create(:saved_search, user: me).id }

      response "200", "seen" do
        run_test!
      end
    end
  end

  # ── A review edited offline carries the values it saw (§10.2) ──
  path "/api/v1/reviews/{id}" do
    patch("edit the caller's hidden review") do
      tags "Reviews"
      consumes "application/json"
      produces "application/json"
      description "OFFLINE §10.2 — `review.base`: per field sent, the value the client saw. A field changed on the " \
                  "author's other device meanwhile is not overwritten (the rest applies) → 409 " \
                  "`code: \"edit_conflict\"` + `fields` (yours / theirs / changed_at)."
      auth_headers
      idempotency_key_header
      parameter name: :id, in: :path, type: :integer
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          review: {
            type: :object,
            properties: {
              rating: { type: :integer, minimum: 1, maximum: 5 }, comment: { type: :string, nullable: true },
              base: { type: :object, additionalProperties: true, description: "the values the client saw" }
            }
          }
        }
      }
      let(:sale) { create(:transaction, :sold) }
      let(:headers) { auth_headers_for(sale.seller) }
      let(:review) { create(:review, sale: sale, reviewer: sale.seller, reviewee: sale.buyer, role: :of_buyer, rating: 3, comment: "ok") }
      let(:id) { review.id }

      response "200", "edited" do
        let(:body) { { review: { rating: 5, base: { rating: 3 } } } }
        run_test! { expect(json.dig("review", "rating")).to eq(5) }
      end

      response "409", "a field changed elsewhere meanwhile: kept, named; the rest applied" do
        let(:body) { { review: { rating: 5, comment: "great", base: { rating: 3, comment: "ok" } } } }
        before { review.update!(rating: 2) }
        run_test! do
          expect(json["code"]).to eq("edit_conflict")
          expect(json["fields"].keys).to eq([ "rating" ])
        end
      end
    end
  end
end
