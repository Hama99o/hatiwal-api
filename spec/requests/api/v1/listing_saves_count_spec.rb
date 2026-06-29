require "rails_helper"

# Saved-by-N social-proof count on listing detail — TASK-V259.
# saves_count is an integer total only (no saver identities), guest-visible,
# and must not introduce an N+1 as the number of SavedListing rows grows.
RSpec.describe "Api::V1::Listings#show saves_count", type: :request do
  let(:listing) { create(:listing, :active) }

  describe "GET /api/v1/listings/:id" do
    it "does not add extra SQL queries as saved-listing rows grow (no N+1)" do
      # Helper to count only data-plane queries — excludes DeviseTokenAuth
      # token-refresh write queries which fire non-deterministically and would
      # otherwise cause spurious failures when the token refresh happens to
      # land inside one measurement window but not the other.
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

      # Warm up: prime the connection pool / schema cache so the baseline
      # measurement does not include one-time setup queries.
      get "/api/v1/listings/#{listing.id}", as: :json

      create(:saved_listing, listing: listing)

      count_1 = [ 0 ]
      data_query_counter.call(count_1) do
        get "/api/v1/listings/#{listing.id}", as: :json
      end
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["saves_count"]).to eq(1)

      create_list(:saved_listing, 9, listing: listing)

      count_10 = [ 0 ]
      data_query_counter.call(count_10) do
        get "/api/v1/listings/#{listing.id}", as: :json
      end
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["listing"]["saves_count"]).to eq(10)

      expect(count_10[0]).to be <= count_1[0] + 1,
        "Expected query count to stay constant (no N+1): " \
        "got #{count_1[0]} queries with 1 saved-listing and " \
        "#{count_10[0]} queries with 10 saved-listings — saves_count N+1 regression"
    end
  end
end
