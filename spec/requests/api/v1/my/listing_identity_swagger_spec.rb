require "swagger_helper"

# OFFLINE §10.6 — the identity travels with the request. Documents `selling_as`
# on the seller's list and its tab counts (the behaviour itself is covered in
# listing_identity_spec.rb).
RSpec.describe "Api::V1::My::Listings identity (OFFLINE §10.6)", type: :request do
  let(:seller)  { create(:user) }
  let(:shop)    { create(:shop, owner: seller) }
  let(:headers) { auth_headers_for(seller) }

  let(:"access-token") { headers["access-token"] }
  let(:client)         { headers["client"] }
  let(:uid)            { headers["uid"] }

  SELLING_AS_DOC = "OFFLINE §10.6 — `me` or a shop id: the identity the app caches this list under, whatever " \
                   "the server's current \"selling as\" (a switch may still be queued on the phone). A shop the " \
                   "caller may not sell as → 422 `code: \"shop_unavailable\"`. Absent (1.1.x apps): the server's " \
                   "current identity, as before.".freeze

  before do
    create(:listing, :active, user: seller)
    create_list(:listing, 2, :active, user: seller, shop: shop)
  end

  path "/api/v1/my/listings" do
    get("list the caller's own listings, for one selling identity") do
      tags "Listings"
      produces "application/json"
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :selling_as, in: :query, type: :string, required: false, description: SELLING_AS_DOC

      response "200", "the identity asked for (here the shop, while the server sells as Me)" do
        let(:selling_as) { shop.id.to_s }

        run_test! { |response| expect(JSON.parse(response.body)["listings"].size).to eq(2) }
      end

      response "422", "a shop the caller may not sell as" do
        let(:selling_as) { create(:shop).id.to_s }

        run_test! { |response| expect(JSON.parse(response.body)["code"]).to eq("shop_unavailable") }
      end
    end
  end

  path "/api/v1/my/listings/status_counts" do
    get("the caller's tab counts, for one selling identity") do
      tags "Listings"
      produces "application/json"
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false
      parameter name: :selling_as, in: :query, type: :string, required: false, description: SELLING_AS_DOC

      response "200", "counts for the identity asked for" do
        let(:selling_as) { "me" }

        run_test! { |response| expect(JSON.parse(response.body)["all"]).to eq(1) }
      end

      response "422", "a shop the caller may not sell as" do
        let(:selling_as) { create(:shop).id.to_s }

        run_test! { |response| expect(JSON.parse(response.body)["code"]).to eq("shop_unavailable") }
      end
    end
  end
end
