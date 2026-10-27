require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1, §10.5) — Idempotency-Key.
#
# The app's outbox sends every queued write with a UUID in Idempotency-Key. On a
# weak network the request can reach the server and its ANSWER be lost: the
# retry then carries the same key and must get the first answer back — one
# listing, one message — instead of doing the write twice.
RSpec.describe "Idempotency-Key", type: :request do
  let(:user)     { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }
  let(:key)      { SecureRandom.uuid }
  let(:params)   { { listing: { title: "Bike", price: 3000, currency: "AFN", category_id: category.id } } }

  def create_listing(key:, body: params, as_user_headers: headers)
    post "/api/v1/my/listings", params: body, headers: as_user_headers.merge("Idempotency-Key" => key), as: :json
  end

  it "a replay returns the FIRST answer — same code, same body — and writes nothing more" do
    expect { create_listing(key: key) }.to change(Listing, :count).by(1)
    first_status = response.status
    first_body = JSON.parse(response.body)
    expect(first_status).to eq(201)
    expect(response.headers["Idempotent-Replayed"]).to be_nil

    expect { create_listing(key: key) }.not_to change(Listing, :count)
    expect(response.status).to eq(first_status)
    expect(JSON.parse(response.body)).to eq(first_body)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  it "the same key with a DIFFERENT request → 422 idempotency_key_reused, nothing written" do
    create_listing(key: key)
    expect do
      create_listing(key: key, body: params.deep_merge(listing: { title: "Another bike" }))
    end.not_to change(Listing, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["code"]).to eq("idempotency_key_reused")
  end

  it "a key whose first request is still running → 409 idempotency_in_progress (the client retries later)" do
    create_listing(key: key)
    # As if that first request were still running (its row is written before the action, completed after).
    IdempotencyKey.find_by!(user: user, key: key).update!(status: :in_progress, response_code: nil, response_body: nil)

    expect { create_listing(key: key) }.not_to change(Listing, :count)
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)["code"]).to eq("idempotency_in_progress")
  end

  # QA audit 2026-10-27 A3: a request that died (the API crashed, OOM) left its
  # row in_progress forever — every retry got 409, and the outbox waited for good.
  it "a key in progress for longer than IN_PROGRESS_TTL is taken over: the retry runs, once" do
    create_listing(key: key)
    # As if that request had died mid-way: no listing, its row left in progress.
    user.listings.last.destroy!
    IdempotencyKey.find_by!(user: user, key: key)
                  .update_columns(status: IdempotencyKey.statuses[:in_progress], response_code: nil,
                                  response_body: nil, updated_at: (IdempotencyKey::IN_PROGRESS_TTL + 1.minute).ago)

    expect { create_listing(key: key) }.to change(Listing, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(IdempotencyKey.find_by!(user: user, key: key)).to be_completed

    expect { create_listing(key: key) }.not_to change(Listing, :count) # replayed from then on
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  it "a key in progress for less than IN_PROGRESS_TTL is still 409 (it may be running)" do
    create_listing(key: key)
    IdempotencyKey.find_by!(user: user, key: key)
                  .update_columns(status: IdempotencyKey.statuses[:in_progress], updated_at: 1.minute.ago)
    expect { create_listing(key: key) }.not_to change(Listing, :count)
    expect(response).to have_http_status(:conflict)
  end

  it "a refusal (4xx) is the answer too: a replay gets the same 422, still no listing" do
    bad = params.deep_merge(listing: { price: -5 })
    create_listing(key: key, body: bad)
    expect(response).to have_http_status(:unprocessable_content)
    errors = JSON.parse(response.body)

    expect { create_listing(key: key, body: bad) }.not_to change(Listing, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)).to eq(errors)
  end

  it "a 5xx is NOT kept: the retry runs again" do
    allow_any_instance_of(Listing).to receive(:save).and_raise(ActiveRecord::StatementInvalid, "boom") # rubocop:disable RSpec/AnyInstance
    expect { create_listing(key: key) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(IdempotencyKey.where(user: user, key: key)).to be_empty

    allow_any_instance_of(Listing).to receive(:save).and_call_original # rubocop:disable RSpec/AnyInstance
    expect { create_listing(key: key) }.to change(Listing, :count).by(1)
  end

  # QA audit 2026-10-27 A1: the throttle runs INSIDE the idempotency wrapper, so
  # a 429 was stored as the key's answer — every retry with that key replayed
  # the 429 (with no Retry-After), long after the window was over.
  it "a 429 is NOT kept: while limited each retry gets a fresh 429 with Retry-After, after the window it runs" do
    30.times { create_listing(key: SecureRandom.uuid) } # the day's limit (30 creates)
    create_listing(key: key)
    expect(response).to have_http_status(:too_many_requests)

    create_listing(key: key)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq(1.day.to_i.to_s)
    expect(response.headers["Idempotent-Replayed"]).to be_nil

    RateLimitable.store.clear # the window is over
    expect { create_listing(key: key) }.to change(Listing, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "keys are per user: another user's same key is a different request" do
    other = create(:user)
    create_listing(key: key)
    expect { create_listing(key: key, as_user_headers: auth_headers_for(other)) }.to change(Listing, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "without the header (every 1.1.x app) nothing changes: two posts, two listings" do
    expect do
      2.times { post "/api/v1/my/listings", params: params, headers: headers, as: :json }
    end.to change(Listing, :count).by(2)
    expect(IdempotencyKey.count).to eq(0)
  end

  it "a malformed key → 422 idempotency_key_invalid" do
    expect { create_listing(key: "x y") }.not_to change(Listing, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["code"]).to eq("idempotency_key_invalid")
  end

  it "a multipart retry (a new random boundary, same photo) is the SAME request: replayed" do
    photo = -> { fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }
    form = lambda do
      { "listing[title]" => "Phone with photo", "listing[price]" => "20000", "listing[currency]" => "AFN",
        "listing[category_id]" => category.id.to_s, "listing[images][]" => photo.call }
    end
    expect do
      post "/api/v1/my/listings", params: form.call, headers: headers.merge("Idempotency-Key" => key)
      post "/api/v1/my/listings", params: form.call, headers: headers.merge("Idempotency-Key" => key)
    end.to change(Listing, :count).by(1)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  it "covers the chat too: a message retried with its key is ONE message" do
    listing = create(:listing, :active)
    conversation = create(:conversation, listing: listing, buyer: user)
    send_message = lambda do
      post "/api/v1/conversations/#{conversation.id}/messages",
           params: { body: "Is it still available?" }, headers: headers.merge("Idempotency-Key" => key), as: :json
    end
    expect { send_message.call }.to change(Message, :count).by(1)
    first = JSON.parse(response.body)
    expect { send_message.call }.not_to change(Message, :count)
    expect(JSON.parse(response.body)).to eq(first)
  end

  context "two concurrent requests with one key", db_truncation: true do
    it "write ONE listing (the unique index decides; the loser answers 409 or the replay)" do
      user
      category
      results = Queue.new
      threads = Array.new(2) do
        Thread.new do
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post "/api/v1/my/listings", params: params.to_json,
                                              headers: headers.merge("Idempotency-Key" => key, "CONTENT_TYPE" => "application/json")
          results << session.response.status
        ensure
          ActiveRecord::Base.connection_pool.release_connection
        end
      end
      threads.each(&:join)
      statuses = Array.new(2) { results.pop }

      expect(Listing.where(user: user).count).to eq(1)
      expect(statuses).to include(201)
      expect(statuses.sort).to satisfy { |s| s == [ 201, 201 ] || s == [ 201, 409 ] }
      expect(IdempotencyKey.where(user: user, key: key).count).to eq(1)
    end
  end

  # §18.2 row 8: "Relaunch all expired" can be queued offline too.
  it "relaunch_expired: a replay returns the first answer (the same count), nothing is relaunched twice" do
    create(:listing, :active, user: user, expires_at: 2.days.ago)
    post "/api/v1/my/listings/relaunch_expired", params: { shop_id: nil }, headers: headers.merge("Idempotency-Key" => key), as: :json
    first = JSON.parse(response.body)
    expect(first["renewed"]).to eq(1)
    post "/api/v1/my/listings/relaunch_expired", params: { shop_id: nil }, headers: headers.merge("Idempotency-Key" => key), as: :json
    expect(JSON.parse(response.body)).to eq(first)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end
end
