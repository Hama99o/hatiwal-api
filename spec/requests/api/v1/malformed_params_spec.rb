require "rails_helper"

# Guards the API against returning a 500 for malformed request params — e.g. a
# client that sends a non-multipart body (so the raw bytes get parsed as
# url-encoded params) or a nested-key type conflict. These must be a clean 400.
# Regression: a broken image upload sent the raw PNG as the body, which Rails
# parsed as url-encoded params and raised ActionDispatch::ParameterTypeError,
# surfacing as a 500.
RSpec.describe "Malformed params handling", type: :request do
  it "returns 400 (not 500) when a nested param key conflicts in type" do
    # `a[b]=1` makes a[b] a String, then `a[b][c]=2` tries to make it a Hash →
    # ActionDispatch::ParameterTypeError (a subclass of ParamError).
    get "/api/v1/listings?a[b]=1&a[b][c]=2"

    expect(response).to have_http_status(:bad_request)
    expect(response).not_to have_http_status(:internal_server_error)
  end

  it "returns 400 (not 500) for a malformed body on an authenticated create" do
    # The real regression: a non-multipart body whose bytes parse as url-encoded
    # params with a nested-key type conflict, on POST /my/listings.
    user = create(:user)
    headers = auth_headers_for(user).merge("CONTENT_TYPE" => "application/x-www-form-urlencoded")

    post "/api/v1/my/listings", params: "listing[a]=1&listing[a][b]=2", headers: headers

    expect(response).to have_http_status(:bad_request)
  end

  # Night QA on qa117 (dd, 2026-10-12): `params.require(:x).permit(...)` met a
  # String or an Array for x and raised NoMethodError, a 500, on every create /
  # update that takes a nested object.
  describe "a nested object sent as a string or an array" do
    let(:user)    { create(:user, :confirmed) } # verification requires a confirmed email first
    let(:headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

    [
      [ :post,  "/api/v1/my/listings", "listing" ],
      [ :post,  "/api/v1/reports",     "report" ],
      [ :patch, "/api/v1/users/me",    "user" ],
      [ :post,  "/api/v1/verification_requests", "verification_request" ]
    ].each do |verb, path, key|
      [ "x", [ "x" ], 5 ].each do |bad|
        it "#{verb.upcase} #{path} with #{key}=#{bad.inspect} is a 400" do
          send(verb, path, params: { key => bad }.to_json, headers: headers)
          expect(response).to have_http_status(:bad_request)
        end
      end
    end
  end

  # Same night: an enum value no client sends was an ArgumentError, a 500.
  describe "an unknown enum value is a 422, not a 500" do
    let(:user)    { create(:user) }
    let(:headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

    it "report reason" do
      listing = create(:listing, :active)
      post "/api/v1/reports", params: { report: { reportable_type: "Listing", reportable_id: listing.id, reason: "bogus" } }.to_json,
                              headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "listing condition" do
      post "/api/v1/my/listings", params: { listing: { title: "Lamp", price: 5, currency: "AFN", category_id: create(:category).id,
                                                       condition: "bogus" } }.to_json,
                                  headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
