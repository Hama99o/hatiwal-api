require "swagger_helper"

# LOC-1 — PATCH /api/v1/users/me/location_guess (hatiwal-mobile/docs/USER_LOCATION.md).
RSpec.describe "Api::V1::Users::LocationGuesses", type: :request do
  let(:user)    { create(:user, city: nil, province: nil) }
  let(:headers) { auth_headers_for(user) }
  let(:herat)   { { latitude: 34.3529, longitude: 62.204 } }

  path "/api/v1/users/me/location_guess" do
    patch "record a clue about where the signed-in user is" do
      tags "Users"
      description "The area the user searched in (`search_area`) or a GPS fix the app already had " \
                  "permission for (`gps`, at most once a day). The newest clue replaces the last. Ignored " \
                  "(still 204) when the user has an own address or the point is outside Afghanistan, " \
                  "Pakistan and Iran. Read the result from `location` on GET /users/me. Never public."
      consumes "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          latitude:  { type: :number, example: 34.3529 },
          longitude: { type: :number, example: 62.204 },
          province:  { type: :string, example: "Herat", nullable: true },
          source:    { type: :string, enum: User::GuessSource::ALL }
        },
        required: %w[latitude longitude source]
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "204", "recorded (or ignored)" do
        let(:body) { herat.merge(source: "search_area") }

        run_test! do
          expect(user.reload).to have_attributes(guessed_source: "search_area", guessed_province: "Herat")
        end
      end

      response "422", "unknown source or missing coordinates" do
        let(:body) { herat.merge(source: "ip") }

        run_test!
      end

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        let(:body)           { herat.merge(source: "gps") }

        run_test!
      end
    end
  end

  def send_guess(params)
    patch "/api/v1/users/me/location_guess", params: params, headers: headers, as: :json
  end

  it "ignores the clue when the user has an own address" do
    user.update!(province: "Kabul")
    send_guess(herat.merge(source: "gps"))
    expect(response).to have_http_status(:no_content)
    expect(user.reload.guessed_latitude).to be_nil
  end

  it "ignores a point abroad" do
    send_guess(latitude: 25.2, longitude: 55.27, source: "gps")
    expect(response).to have_http_status(:no_content)
    expect(user.reload.guessed_latitude).to be_nil
  end

  it "has its error messages in all four locales" do
    User::SUPPORTED_LANGUAGES.each do |locale|
      I18n.with_locale(locale) do
        %w[location.errors.unknown_source location.errors.coordinates_required].each do |key|
          expect(I18n.t(key, raise: true)).to be_present
        end
      end
    end
  end

  it "rejects coordinates that are not numbers" do
    send_guess(latitude: "x", longitude: 62.2, source: "gps")
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "is rate-limited per user" do
    60.times { send_guess(herat.merge(source: "search_area")) }
    expect(response).to have_http_status(:no_content)
    send_guess(herat.merge(source: "search_area"))
    expect(response).to have_http_status(:too_many_requests)
  end

  it "shows up in GET /users/me as the location block" do
    send_guess(herat.merge(source: "search_area"))
    get "/api/v1/users/me", headers: headers, as: :json
    expect(JSON.parse(response.body)["user"]["location"]).to eq(
      "latitude" => 34.3529, "longitude" => 62.204, "province" => "Herat", "source" => "guess"
    )
  end
end

RSpec.describe "Listing create/update teaches the guess", type: :request do
  let(:user)     { create(:user, city: nil, province: nil) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category) }
  let(:params) do
    { listing: { title: "Rug", description: "Hand-made", price: 9000, currency: "AFN", category_id: category.id,
                 location: "Herat, City Center", latitude: 34.3529, longitude: 62.204 } }
  end

  it "records where a seller without an own address posted" do
    post "/api/v1/my/listings", params: params, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(user.reload).to have_attributes(guessed_source: "listing", guessed_province: "Herat")
  end

  it "keeps a seller's own Kabul address after they post in Herat" do
    user.update!(province: "Kabul", latitude: 34.5553, longitude: 69.2075)
    post "/api/v1/my/listings", params: params, headers: headers, as: :json
    expect(user.reload).to have_attributes(guessed_latitude: nil, province: "Kabul")
    expect(user.effective_location[:province]).to eq("Kabul")
  end

  it "records the new point when the seller moves the listing" do
    listing = create(:listing, user: user, latitude: nil, longitude: nil)
    patch "/api/v1/my/listings/#{listing.id}",
          params: { listing: { latitude: 31.6133, longitude: 65.7101, location: "Kandahar" } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload.guessed_province).to eq("Kandahar")
  end
end
