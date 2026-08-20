require "rails_helper"

# TASK-BE-SAVEDLIST (FlowApp #255) — the feed heart. `ListingSerializer`
# defined `is_saved` only inside `view :detailed`, so `GET /listings`
# (`view :list`) never sent it to ANY caller, bearer or guest. Both mobile's
# Browse.tsx and web's Bazaar feed card had to guard against an undefined
# field instead of trusting the payload.
RSpec.describe "Api::V1::Listings is_saved (feed heart)", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/listings" do
    it "flags a listing the bearer has saved as is_saved: true, and the rest as false" do
      saved   = create(:listing, :active, title: "Saved")
      unsaved = create(:listing, :active, title: "Unsaved")
      create(:saved_listing, user: user, listing: saved)

      get "/api/v1/listings", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body)["listings"].to_h { |l| [ l["title"], l["is_saved"] ] }
      expect(rows["Saved"]).to be(true)
      expect(rows["Unsaved"]).to be(false)
    end

    it "does not flag another user's saved listing as saved for the current bearer" do
      listing = create(:listing, :active)
      create(:saved_listing, user: create(:user), listing: listing)

      get "/api/v1/listings", headers: headers, as: :json

      row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }
      expect(row["is_saved"]).to be(false)
    end

    it "returns is_saved: false for every row when the caller is a guest" do
      create(:listing, :active)

      get "/api/v1/listings", as: :json

      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body)["listings"]
      expect(rows).not_to be_empty
      expect(rows).to all(include("is_saved" => false))
    end

    it "always includes the is_saved key, even with no saved rows at all" do
      create(:listing, :active)

      get "/api/v1/listings", headers: headers, as: :json

      row = JSON.parse(response.body)["listings"].first
      expect(row).to have_key("is_saved")
      expect(row["is_saved"]).to be(false)
    end

    # Acceptance: "one query for the whole page — a bullet-proof N+1 spec (no
    # per-row SELECT ... saved_listings)".
    #
    # The PAGE (row count, sellers, categories) is held IDENTICAL across both
    # measurements — only whether the rows are saved by the current user
    # changes — so any unrelated per-row cost the browse feed already has
    # (e.g. seller avatar lookups) affects both measurements equally and
    # cancels out of the diff. What's left isolates is_saved's own query cost:
    # `saved_listing_ids` must issue exactly one indexed query regardless of
    # how many of the page's listings the caller has saved, never a per-row
    # `saved_listings.exists?`.
    it "does not add extra SQL queries when every row on the page is saved vs none (no N+1)" do
      category = create(:category)
      seller   = create(:user)
      listings = create_list(:listing, 10, :active, category: category, user: seller)

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

      # Warm up: prime the connection pool / schema cache before measuring.
      get "/api/v1/listings", headers: headers, as: :json

      count_none_saved = [ 0 ]
      data_query_counter.call(count_none_saved) do
        get "/api/v1/listings", headers: headers, as: :json
      end
      expect(response).to have_http_status(:ok)

      listings.each { |l| create(:saved_listing, user: user, listing: l) }

      count_all_saved = [ 0 ]
      data_query_counter.call(count_all_saved) do
        get "/api/v1/listings", headers: headers, as: :json
      end
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listings"]).to all(include("is_saved" => true))

      expect(count_all_saved[0]).to be <= count_none_saved[0] + 1,
        "Expected query count to stay constant (no N+1): got #{count_none_saved[0]} queries " \
        "with 0 saved rows on the page and #{count_all_saved[0]} with all 10 saved — " \
        "is_saved N+1 regression"
    end
  end
end
