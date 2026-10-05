require "rails_helper"

# THE v1.0.4 CONTRACT, MEASURED RATHER THAN ARGUED.
#
# v1.0.4 of the app is live in both stores, can only talk to production, and
# sends no version header, so the API cannot tell it apart from a newer app.
# Every response a serializer change touches is served to it as-is. This spec
# pins what v1.0.4 was built against: the response SHAPE of the endpoints it
# reads, for an ordinary (non-support) user, plus the ORDER of the rows.
#
# spec/fixtures/api_contract/v1_0_4.json was recorded on the code BEFORE
# support messaging (6bf6824), from this exact scenario. Pass condition:
#   - every key in the recording is still there, in the same relative order
#   - no existing key changed type (null/string/integer/…)
#   - every array has the same number of rows, in the same order
#   - a key that is NEW must be listed in ALLOWED_ADDITIONS — additions are
#     safe for an old client, but they are made on purpose, not by accident
#
# If this fails, the change is a break for v1.0.4, however reasonable it looks.
# Re-record ONLY when that app version is no longer in use:
#   RECORD_API_CONTRACT=1 bundle exec rspec spec/requests/api/v1/api_contract_v1_0_4_spec.rb
RSpec.describe "API contract served to app v1.0.4", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  FIXTURE = Rails.root.join("spec/fixtures/api_contract/v1_0_4.json")

  # Additive keys since the recording, each with the reason it is safe.
  ALLOWED_ADDITIONS = {
    # Support messaging. Always "listing" for every pre-existing conversation.
    "conversations[].kind" => "support messaging",
    "conversation.kind" => "support messaging",
    # SHOP-1. Always null for a listing that is not in a shop — i.e. every row
    # an old client can meet until someone opens a shop; it ignores the key.
    "conversations[].shop" => "SHOP-1 shop block (null = personal)",
    "conversation.shop" => "SHOP-1 shop block (null = personal)",
    "listings[].shop" => "SHOP-1 shop block (null = personal)",
    "listing.shop" => "SHOP-1 shop block (null = personal)"
  }.freeze

  # Values are irrelevant; their JSON TYPE is the contract.
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

  # path => { "types" => [...], "keys" => [...] (objects), "count" => n (arrays) }
  def shape_of(value, path = "", acc = {})
    entry = (acc[path] ||= { "types" => [] })
    entry["types"] = (entry["types"] | [ json_type(value) ]).sort
    case value
    when Hash
      entry["keys"] = (entry["keys"] || []) | value.keys
      value.each { |k, v| shape_of(v, path.empty? ? k : "#{path}.#{k}", acc) }
    when Array
      entry["count"] = value.size
      value.each { |v| shape_of(v, "#{path}[]", acc) }
    end
    acc
  end

  # A deterministic inbox: two threads as buyer (one empty), one as seller, and
  # one whose listing was taken down. Distinct last_message_at values so the
  # existing ORDER BY (last_message_at DESC NULLS LAST, created_at DESC) has a
  # single right answer the recording can pin.
  let(:viewer) { create(:user, firstname: "Viewer", lastname: "One") }

  # Each record a minute after the last, so no two rows tie on created_at and
  # every ORDER BY in these endpoints has exactly one right answer.
  def tick = travel(1.minute)

  def build_scenario
    travel_to Time.zone.parse("2026-09-01 10:00")
    begin
      alpha = create(:listing, :active, title: "Alpha Phone", user: create(:user))
      tick
      bravo = create(:listing, :active, title: "Bravo Bike", user: create(:user))
      tick
      chair = create(:listing, :active, title: "Charlie Chair", user: viewer)
      tick
      gone  = create(:listing, :active, title: "Delta Desk", user: create(:user))
      tick
      buyer = create(:user, firstname: "Buyer", lastname: "Two")
      tick

      @alpha_thread = create(:conversation, buyer: viewer, listing: alpha)
      tick
      create(:message, conversation: @alpha_thread, user: viewer, kind: :text, body: "Is it available?")
      tick
      create(:message, conversation: @alpha_thread, user: alpha.user, kind: :text, body: "Yes")
      tick
      create(:message, conversation: @alpha_thread, user: viewer, kind: :offer, body: "9000|AFN|1")
      tick
      @alpha_thread.update_columns(last_message_at: 1.hour.ago)

      create(:conversation, buyer: viewer, listing: bravo) # empty: last_message_at NULL
      tick

      chair_thread = create(:conversation, buyer: buyer, listing: chair)
      tick
      create(:message, conversation: chair_thread, user: buyer, kind: :text, body: "Still selling?")
      tick
      chair_thread.update_columns(last_message_at: 2.hours.ago)

      @gone_thread = create(:conversation, buyer: viewer, listing: gone)
      tick
      create(:message, conversation: @gone_thread, user: viewer, kind: :text, body: "Hello")
      tick
      @gone_thread.update_columns(last_message_at: 3.hours.ago)
      gone.update_columns(removed_at: 1.minute.ago)

      @alpha = alpha
    ensure
      travel_back
    end
  end

  def endpoints
    headers = auth_headers_for(viewer)
    {
      "inbox" => [ "/api/v1/conversations", {} ],
      "inbox_buying" => [ "/api/v1/conversations", { role: "buying" } ],
      "inbox_selling" => [ "/api/v1/conversations", { role: "selling" } ],
      "inbox_search" => [ "/api/v1/conversations", { search: "Phone" } ],
      "thread" => [ "/api/v1/conversations/#{@alpha_thread.id}", {} ],
      "thread_removed_listing" => [ "/api/v1/conversations/#{@gone_thread.id}", {} ],
      "messages" => [ "/api/v1/conversations/#{@alpha_thread.id}/messages", {} ],
      "listings" => [ "/api/v1/listings", {} ],
      "listing" => [ "/api/v1/listings/#{@alpha.id}", {} ]
    }.transform_values do |(url, params)|
      get url, params: params, headers: headers
      body = JSON.parse(response.body)
      { "status" => response.status, "shape" => shape_of(body), "order" => row_labels(body) }
    end
  end

  # Row order by something stable across runs (ids are not).
  def row_labels(body)
    rows = body["conversations"] || body["messages"] || body["listings"]
    return nil unless rows

    rows.map { |r| r.dig("listing", "title") || r["title"] || r["body"] || (r["listing_deleted"] ? "(removed listing)" : "?") }
  end

  it "serves v1.0.4 exactly what it was built against, plus only allowed additions" do
    build_scenario
    current = endpoints

    if ENV["RECORD_API_CONTRACT"]
      FileUtils.mkdir_p(FIXTURE.dirname)
      File.write(FIXTURE, JSON.pretty_generate(current) + "\n")
      skip "recorded #{FIXTURE}"
    end

    recorded = JSON.parse(File.read(FIXTURE))
    problems = []

    recorded.each do |name, before|
      after = current.fetch(name)
      problems << "#{name}: status #{before['status']} -> #{after['status']}" if before["status"] != after["status"]
      problems << "#{name}: row order #{before['order'].inspect} -> #{after['order'].inspect}" if before["order"] != after["order"]

      before["shape"].each do |path, b|
        a = after["shape"][path]
        next problems << "#{name}: #{path} REMOVED" unless a

        problems << "#{name}: #{path} type #{b['types']} -> #{a['types']}" if b["types"] != a["types"]
        problems << "#{name}: #{path} count #{b['count']} -> #{a['count']}" if b["count"] != a["count"]
        if b["keys"] && (a["keys"] & b["keys"]) != b["keys"]
          problems << "#{name}: #{path} key order #{b['keys']} -> #{a['keys'] & b['keys']}"
        end
      end

      (after["shape"].keys - before["shape"].keys).each do |path|
        problems << "#{name}: #{path} ADDED but not in ALLOWED_ADDITIONS" unless ALLOWED_ADDITIONS.key?(path)
      end
    end

    expect(problems).to be_empty, "v1.0.4 contract broken:\n  #{problems.join("\n  ")}"
  end
end
