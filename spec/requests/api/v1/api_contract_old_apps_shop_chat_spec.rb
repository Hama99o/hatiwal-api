require "rails_helper"

# OLD APPS (v1.0.4 … 1.1.5) AND A "MESSAGE SHOP" CHAT (no product).
#
# Old apps send no version header, so they get exactly what new apps get. They
# have never seen a chat without a product — but they HAVE always handled a
# chat whose product was REMOVED: `listing: null` + `listing_deleted: true`.
# That shape is recorded in spec/fixtures/api_contract/v1_0_4.json as
# `thread_removed_listing` (and `messages`). This spec proves a Message-shop
# chat looks, to an old app, exactly like that thread: every recorded key at
# the same path with a recorded type, plus only additive keys (`shop_chat`,
# `shop`, `kind`, `as_shop`, …), and the actions an old app performs on such
# a thread still work (open, read, send text, mark read).
RSpec.describe "Old apps on a Message-shop chat", type: :request do
  RECORDING = JSON.parse(Rails.root.join("spec/fixtures/api_contract/v1_0_4.json").read)

  let(:owner) { create(:user) }
  let(:shop) { create(:shop, owner: owner) }
  let(:buyer) { create(:user) }
  let!(:chat) { Conversations::StartShopService.new(buyer: buyer, shop: shop, message_body: "Salaam").call }

  def json_type(value)
    case value
    when nil then "null"
    when true, false then "boolean"
    when Integer then "integer"
    when Float then "float"
    when String then "string"
    when Array then "array"
    when Hash then "object"
    end
  end

  def shape_of(value, path = "", acc = {})
    entry = (acc[path] ||= { "types" => [] })
    entry["types"] = (entry["types"] | [ json_type(value) ]).sort
    case value
    when Hash
      entry["keys"] = (entry["keys"] || []) | value.keys
      value.each { |k, v| shape_of(v, path.empty? ? k : "#{path}.#{k}", acc) }
    when Array
      value.each { |v| shape_of(v, "#{path}[]", acc) }
    end
    acc
  end

  # Every recorded path is still there; every recorded key at that path is still
  # there; a value's type is one the recording saw there (a URL may be null in
  # one scenario and a string in another, so either is fine for *_url).
  def problems(recorded, actual)
    recorded.flat_map do |path, rec|
      act = actual[path]
      next [ "#{path}: missing" ] unless act

      missing = (rec["keys"] || []) - (act["keys"] || [])
      allowed = rec["types"] | (path.end_with?("_url") ? %w[null string] : [])
      wrong = act["types"] - allowed
      [ *("#{path}: keys missing #{missing}" if missing.any?), *("#{path}: types #{wrong} not in #{allowed}" if wrong.any?) ]
    end
  end

  %i[owner buyer].each do |who|
    context "seen by the #{who}" do
      let(:viewer) { who == :owner ? owner : buyer }
      let(:headers) { auth_headers_for(viewer) }

      it "the thread is shaped exactly like the recorded removed-listing thread (+ additions only)" do
        get "/api/v1/conversations/#{chat.id}", headers: headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(problems(RECORDING["thread_removed_listing"]["shape"], shape_of(body))).to eq([])
        # The values an old app branches on: a "removed product" thread, never a live listing.
        expect(body["conversation"]).to include("listing" => nil, "listing_deleted" => true, "kind" => "listing",
                                               "shop_chat" => true, "status" => "open")
      end

      it "its messages are shaped like the recorded messages" do
        get "/api/v1/conversations/#{chat.id}/messages", headers: headers
        expect(response).to have_http_status(:ok)
        recorded = RECORDING["messages"]["shape"].reject { |path, _| path.start_with?("meta") }
        actual = shape_of(JSON.parse(response.body))
        expect(problems(recorded, actual)).to eq([])
      end

      it "the inbox row is shaped like a recorded inbox row" do
        get "/api/v1/conversations", headers: headers
        rows = JSON.parse(response.body)["conversations"]
        row = rows.find { |r| r["id"] == chat.id }
        expect(row).to include("listing" => nil, "listing_deleted" => true)
        recorded = RECORDING["inbox"]["shape"].select { |path, _| path.start_with?("conversations[]") }
        actual = shape_of({ "conversations" => [ row ] })
        # The recording has no removed-listing ROW (only a removed-listing THREAD,
        # checked above), so its row `listing` is always an object. A row with
        # `listing: null` + `listing_deleted: true` is that same removed-listing
        # case, which old apps guard (`item.listing?.…`), so `listing` may be null.
        relevant = recorded.reject { |path, _| path.start_with?("conversations[].listing") }
        expect(row["listing"]).to be_nil
        expect(problems(relevant, actual)).to eq([])
      end

      it "what an old app does on that thread works: send text, mark read" do
        post "/api/v1/conversations/#{chat.id}/messages", params: { kind: "text", body: "From an old app" }, headers: headers
        expect(response).to have_http_status(:created)
        put "/api/v1/conversations/#{chat.id}/mark_read", headers: headers
        expect(response).to have_http_status(:no_content)
      end
    end
  end

  it "an old app's offer/meetup on it is refused cleanly (422 with errors), never a 500" do
    post "/api/v1/conversations/#{chat.id}/messages", params: { kind: "meetup_proposal", body: "Tomorrow" },
                                                       headers: auth_headers_for(owner)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"]).to be_present
  end
end
