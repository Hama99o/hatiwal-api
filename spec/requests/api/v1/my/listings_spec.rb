require "rails_helper"

RSpec.describe "Api::V1::My::Listings", type: :request do
  let(:user)     { create(:user) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }

  describe "GET /api/v1/my/listings" do
    it "requires authentication" do
      get "/api/v1/my/listings", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns only the current user's listings" do
      mine = create(:listing, user: user)
      create(:listing) # someone else's

      get "/api/v1/my/listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      listings = JSON.parse(response.body)["listings"]
      expect(listings.map { |l| l["id"] }).to eq([ mine.id ])
      expect(listings.first).to have_key("image_urls")
      expect(listings.first["image_urls"]).to be_an(Array)
    end

    it "filters by status" do
      active = create(:listing, :active, user: user)
      create(:listing, :draft, user: user)

      get "/api/v1/my/listings?status=active", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ active.id ])
    end

    it "status=active excludes expired listings (clean partition with the Expired tab)" do
      live    = create(:listing, :active, user: user, expires_at: 10.days.from_now)
      create(:listing, :active, user: user, expires_at: 2.days.ago) # expired

      get "/api/v1/my/listings?status=active", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ live.id ])
    end

    it "status=expired returns only active listings past their expiry" do
      expired = create(:listing, :active, user: user, expires_at: 2.days.ago)
      create(:listing, :active, user: user, expires_at: 10.days.from_now) # live
      create(:listing, :draft, user: user) # drafts never expire

      get "/api/v1/my/listings?status=expired", headers: headers, as: :json

      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).to eq([ expired.id ])
    end

    it "executes a constant number of queries regardless of listing count (no N+1)" do
      image_fixture = Rails.root.join("spec/fixtures/files/test_image.jpg")

      attach_image = lambda do |listing|
        listing.images.attach(
          io:           File.open(image_fixture),
          filename:     "photo.jpg",
          content_type: "image/jpeg"
        )
      end

      # Helper to count only data-plane queries — excludes DeviseTokenAuth
      # token-refresh write queries (SAVEPOINT / UPDATE users SET tokens /
      # RELEASE SAVEPOINT) which fire non-deterministically and would otherwise
      # cause spurious failures when the token refresh happens to land inside
      # one measurement window but not the other.
      data_query_counter = lambda do |counter_ref, &block|
        ActiveSupport::Notifications.subscribed(
          lambda { |*, payload|
            sql = payload[:sql].to_s
            next if sql.start_with?("SAVEPOINT", "RELEASE SAVEPOINT")
            next if sql =~ /\AUPDATE "users" SET "tokens"/

            counter_ref[0] += 1
          },
          "sql.active_record",
          &block
        )
      end

      # Warm up: prime the Rails connection pool, schema cache, and auth token
      # caches so the baseline does not include any one-time setup queries.
      get "/api/v1/my/listings", headers: headers, as: :json

      # ---- baseline: 1 listing with an image --------------------------------
      listing_1 = create(:listing, user: user)
      attach_image.call(listing_1)

      count_1 = [ 0 ]
      data_query_counter.call(count_1) do
        get "/api/v1/my/listings", headers: headers, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listings"].length).to eq(1)

      # ---- scale up: 3 distinct listings each with their own image ----------
      # Titles are made unique so the Rails query cache cannot mask a missing
      # eager-load by returning a previously cached result for the same query.
      listing_2 = create(:listing, user: user, title: "N+1 Guard Listing Two")
      listing_3 = create(:listing, user: user, title: "N+1 Guard Listing Three")
      attach_image.call(listing_2)
      attach_image.call(listing_3)
      listing_1.update_columns(title: "N+1 Guard Listing One")

      count_3 = [ 0 ]
      data_query_counter.call(count_3) do
        get "/api/v1/my/listings", headers: headers, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listings"].length).to eq(3)

      # Adding 2 more listings (distinct images, categories, conversations) must not
      # grow the query count. Allow up to 3 queries tolerance for per-request
      # overhead (token-refresh, minor schema warmup) that may vary between
      # measurements but must never scale O(N) with listing count.
      expect(count_3[0]).to be <= count_1[0] + 3,
        "Expected query count to be constant (no N+1): " \
        "got #{count_1[0]} with 1 listing and #{count_3[0]} with 3 listings"
    end
  end

  describe "GET /api/v1/my/listings/:id" do
    it "returns the owner's listing in detail" do
      listing = create(:listing, user: user)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["id"]).to eq(listing.id)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "includes views_count and conversations_count in the :detailed response" do
      listing = create(:listing, user: user)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["listing"]
      expect(body).to have_key("views_count")
      expect(body["views_count"]).to be_a(Integer)
      expect(body).to have_key("conversations_count")
      expect(body["conversations_count"]).to be_a(Integer)
    end

    it "conversations_count reflects actual conversation records" do
      listing = create(:listing, :active, user: user)
      buyer   = create(:user)
      create(:conversation, listing: listing, buyer: buyer, seller: user)
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["listing"]
      expect(body["conversations_count"]).to eq(1)
    end
  end

  describe "POST /api/v1/my/listings" do
    let(:valid_params) do
      {
        listing: {
          title:       "iPhone 13 Pro",
          description: "Used, excellent condition",
          price:       45000,
          currency:    "AFN",
          category_id: category.id,
          location:    "Kabul, Afghanistan"
        }
      }
    end

    it "creates a draft listing owned by the current user" do
      expect do
        post "/api/v1/my/listings", params: valid_params, headers: headers, as: :json
      end.to change(user.listings, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["listing"]
      expect(body["title"]).to eq("iPhone 13 Pro")
      expect(body["status"]).to eq("draft")
    end

    it "422s on invalid params" do
      params = valid_params.deep_merge(listing: { price: -5 })
      expect do
        post "/api/v1/my/listings", params: params, headers: headers, as: :json
      end.not_to change(Listing, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end
  end

  describe "POST /api/v1/my/listings with images (multipart)" do
    it "accepts image uploads via FormData and attaches them" do
      image = fixture_file_upload(
        Rails.root.join("spec/fixtures/files/test_image.jpg"),
        "image/jpeg"
      )

      expect do
        post "/api/v1/my/listings",
             params: {
               "listing[title]"       => "Phone with photo",
               "listing[price]"       => "20000",
               "listing[currency]"    => "AFN",
               "listing[category_id]" => category.id.to_s,
               "listing[images][]"    => image
             },
             headers: headers
      end.to change(user.listings, :count).by(1)

      expect(response).to have_http_status(:created)
    end
  end

  describe "PUT /api/v1/my/listings/:id image handling (no data loss)" do
    let(:listing) { create(:listing, user: user) }

    before do
      listing.images.attach(io: StringIO.new("first"), filename: "first.jpg", content_type: "image/jpeg")
    end

    it "appends new photos without destroying existing ones" do
      new_image = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg")
      expect(listing.images.count).to eq(1)

      put "/api/v1/my/listings/#{listing.id}",
          params: { "listing[title]" => "Updated", "listing[images][]" => new_image },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(listing.reload.images.count).to eq(2)
    end

    it "purges only the photos named in removed_image_ids" do
      listing.images.attach(io: StringIO.new("second"), filename: "second.jpg", content_type: "image/jpeg")
      expect(listing.images.count).to eq(2)
      removed = listing.images.first.blob.signed_id

      put "/api/v1/my/listings/#{listing.id}",
          params: { "listing[title]" => "Updated", "listing[removed_image_ids][]" => removed },
          headers: headers

      expect(response).to have_http_status(:ok)
      expect(listing.reload.images.count).to eq(1)
    end

    it "a text-only edit leaves every photo intact" do
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "Just text" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.images.count).to eq(1)
    end

    it "exposes image_attachments with stable ids in the detailed view" do
      get "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      atts = JSON.parse(response.body)["listing"]["image_attachments"]
      expect(atts).to be_an(Array)
      expect(atts.first).to include("id", "url")
    end
  end

  describe "PUT /api/v1/my/listings/:id" do
    it "updates the owner's listing" do
      listing = create(:listing, user: user, title: "Old title")
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "New title" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.title).to eq("New title")
    end

    it "updates the address field" do
      listing = create(:listing, user: user)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { address: "Near Blue Mosque, Shar-e-Naw" } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(listing.reload.address).to eq("Near Blue Mosque, Shar-e-Naw")
      expect(JSON.parse(response.body)["listing"]).to have_key("address")
    end

    it "422s on invalid update" do
      listing = create(:listing, user: user)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "" } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      put "/api/v1/my/listings/#{listing.id}",
          params: { listing: { title: "x" } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/my/listings/:id" do
    it "soft-removes the owner's listing (keeps the record so chats survive)" do
      listing = create(:listing, user: user)
      expect do
        delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      end.not_to change(Listing, :count)
      expect(response).to have_http_status(:no_content)
      expect(listing.reload.removed_at).to be_present
    end

    it "keeps conversations and messages about a deleted listing" do
      listing = create(:listing, :active, user: user)
      buyer   = create(:user)
      convo   = create(:conversation, buyer: buyer, listing: listing)
      msg     = create(:message, conversation: convo, user: buyer, body: "still here?")

      delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json

      expect(response).to have_http_status(:no_content)
      expect(Conversation.exists?(convo.id)).to be(true)
      expect(Message.exists?(msg.id)).to be(true)
    end

    it "hides a soft-removed listing from My Shop" do
      listing = create(:listing, :active, user: user)
      delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json

      get "/api/v1/my/listings", headers: headers, as: :json
      ids = JSON.parse(response.body)["listings"].map { |l| l["id"] }
      expect(ids).not_to include(listing.id)
    end

    it "404s for another user's listing" do
      listing = create(:listing)
      delete "/api/v1/my/listings/#{listing.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "lifecycle transitions" do
    describe "PUT publish" do
      it "publishes a draft" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(draft.reload).to be_active
      end

      it "forbids publishing a non-draft" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT reserve" do
      it "reserves an active listing" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/reserve", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(active.reload).to be_reserved
      end

      it "forbids reserving a draft" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/reserve", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT sold" do
      it "marks a reserved listing as sold" do
        reserved = create(:listing, :reserved, user: user)
        put "/api/v1/my/listings/#{reserved.id}/sold", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(reserved.reload).to be_sold
      end

      it "marks an active listing as sold (sell directly)" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/sold", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(active.reload).to be_sold
      end

      it "forbids selling a draft" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/sold", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "cannot reopen a sold listing (terminal)" do
        sold = create(:listing, :sold, user: user)
        put "/api/v1/my/listings/#{sold.id}/activate", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
        put "/api/v1/my/listings/#{sold.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT unpublish" do
      it "takes an active listing back to draft" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/unpublish", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(active.reload).to be_draft
      end

      it "forbids unpublishing a non-active listing" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/unpublish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT activate" do
      it "undoes a reservation (reserved → active)" do
        reserved = create(:listing, :reserved, user: user)
        put "/api/v1/my/listings/#{reserved.id}/activate", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(reserved.reload).to be_active
      end

      it "forbids activating a non-reserved listing" do
        active = create(:listing, :active, user: user)
        put "/api/v1/my/listings/#{active.id}/activate", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "PUT publish sets the expiry clock" do
      it "a created draft has no expiry — the clock starts at publish, not at draft creation" do
        post "/api/v1/my/listings",
             params: { listing: { title: "T", price: 100, currency: "AFN", category_id: create(:category).id } },
             headers: headers, as: :json
        expect(response).to have_http_status(:created)
        listing = user.listings.order(:created_at).last
        expect(listing.status).to eq("draft")
        expect(listing.expires_at).to be_nil
      end

      it "stamps expires_at when a draft is published" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/publish", headers: headers, as: :json
        expect(draft.reload.expires_at).to be_present
        expect(draft.expires_at).to be > Time.current
      end
    end

    describe "PUT renew" do
      it "restarts the expiry clock on an expired active listing" do
        listing = create(:listing, :active, user: user, expires_at: 2.days.ago)
        expect(listing.reload).to be_expired

        put "/api/v1/my/listings/#{listing.id}/renew", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(listing.reload.expires_at).to be > Time.current
        expect(listing).not_to be_expired
      end

      it "forbids renewing a non-active listing" do
        draft = create(:listing, :draft, user: user)
        put "/api/v1/my/listings/#{draft.id}/renew", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    # ── negotiable field ────────────────────────────────────────────────────────
    describe "negotiable flag" do
      it "defaults to true when negotiable param is omitted on create" do
        post "/api/v1/my/listings",
             params: { listing: { title: "Test", price: 500, currency: "AFN", category_id: category.id } },
             headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["listing"]["negotiable"]).to be(true)
        expect(user.listings.last.negotiable).to be(true)
      end

      it "persists negotiable: false when explicitly set on create" do
        post "/api/v1/my/listings",
             params: { listing: { title: "Firm Price Item", price: 1000, currency: "AFN",
                                  category_id: category.id, negotiable: false } },
             headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["listing"]["negotiable"]).to be(false)
        expect(user.listings.last.negotiable).to be(false)
      end

      it "can toggle negotiable from false to true on update (while draft)" do
        draft = create(:listing, :draft, user: user, negotiable: false)

        put "/api/v1/my/listings/#{draft.id}",
            params: { listing: { negotiable: true } },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listing"]["negotiable"]).to be(true)
        expect(draft.reload.negotiable).to be(true)
      end

      it "can toggle negotiable from true to false on update (while draft)" do
        draft = create(:listing, :draft, user: user, negotiable: true)

        put "/api/v1/my/listings/#{draft.id}",
            params: { listing: { negotiable: false } },
            headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["listing"]["negotiable"]).to be(false)
        expect(draft.reload.negotiable).to be(false)
      end

      it "serializes negotiable in the :list view" do
        create(:listing, user: user, negotiable: false)

        get "/api/v1/my/listings", headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        listings = JSON.parse(response.body)["listings"]
        # The newly created listing with negotiable: false should appear
        firm = listings.find { |l| l["negotiable"] == false }
        expect(firm).not_to be_nil
      end
    end
  end
end
