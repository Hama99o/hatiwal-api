require "swagger_helper"

# UPD-1 — GET /api/v1/app_config (public). hatiwal-mobile/docs/FORCE_UPDATE.md
RSpec.describe "Api::V1::AppConfig", type: :request do
  before { create(:app_release_setting) } # android: min 1.1.6, latest 1.1.7; ios: latest 1.1.7

  path "/api/v1/app_config" do
    get "which app version must run (force update / reminder)" do
      tags "App"
      description "Public. Platform from X-App-Platform (or ?platform=), version from X-App-Version (or ?version=). " \
                  "status: ok | soft (below latest: banner) | blocked (below minimum: full-screen block). A missing " \
                  "or malformed version is always ok. Cache-Control: public, max-age=60; Vary on both headers."
      produces "application/json"
      parameter name: :"X-App-Platform", in: :header, type: :string, required: false, enum: %w[ios android]
      parameter name: :"X-App-Version", in: :header, type: :string, required: false, example: "1.1.6"

      response "200", "blocked below the minimum" do
        schema type: :object,
               properties: {
                 platform: { type: :string, nullable: true },
                 min_version: { type: :string, nullable: true },
                 latest_version: { type: :string, nullable: true },
                 store_url: { type: :string, nullable: true },
                 status: { type: :string, enum: AppReleaseSetting::STATUSES },
                 listing_rules: {
                   type: :object,
                   description: "OFFLINE §8.6 / §10.4 — the server's listing limits, so a listing made offline " \
                                "is checked on the phone with the server's own numbers (Listing.client_rules)",
                   properties: {
                     title_max: { type: :integer }, description_max: { type: :integer }, price_max: { type: :number },
                     quantity_min: { type: :integer }, quantity_max: { type: :integer }, max_photos: { type: :integer },
                     photo_required_to_publish: { type: :boolean }, video_max_seconds: { type: :integer },
                     video_max_bytes: { type: :integer }
                   }
                 },
                 features: {
                   type: :object,
                   description: "Server features an app may only offer when this server has them",
                   properties: {
                     image_search: { type: :boolean, description: "search by image (docs/IMAGE_SEARCH.md): show the camera button" }
                   }
                 }
               },
               required: %w[platform status]
        let(:"X-App-Platform") { "android" }
        let(:"X-App-Version") { "1.1.5" }

        run_test! do
          body = JSON.parse(response.body)
          expect(body).to include("platform" => "android", "min_version" => "1.1.6", "latest_version" => "1.1.7", "status" => "blocked")
          expect(body["store_url"]).to include("com.hatiwal.app")
          expect(response.headers["Cache-Control"]).to include("private").and include("max-age=60")
        end
      end
    end
  end

  def config_for(platform, version, query: false)
    if query
      get "/api/v1/app_config", params: { platform: platform, version: version }
    else
      get "/api/v1/app_config", headers: { "X-App-Platform" => platform, "X-App-Version" => version }.compact
    end
    JSON.parse(response.body)
  end

  it "is soft between minimum and latest, ok at latest" do
    expect(config_for("android", "1.1.6")["status"]).to eq("soft")
    expect(config_for("android", "1.1.7")["status"]).to eq("ok")
  end

  it "reads each platform's own settings" do
    expect(config_for("ios", "1.1.5")["status"]).to eq("soft") # iOS has no minimum
    expect(config_for("ios", "1.1.5")["store_url"]).to include("apps.apple.com")
  end

  it "never blocks a garbage, missing or unknown version or platform" do
    expect(config_for("android", "garbage")["status"]).to eq("ok")
    expect(config_for("android", nil)["status"]).to eq("ok")
    expect(config_for("web", "0.0.1")).to include("platform" => nil, "status" => "ok")
  end

  it "accepts the query params too" do
    expect(config_for("android", "1.1.5", query: true)["status"]).to eq("blocked")
  end

  it "needs no sign-in and makes no per-user query" do
    queries = []
    ActiveSupport::Notifications.subscribed(->(*, p) { queries << p[:sql] if p[:sql].start_with?("SELECT") }, "sql.active_record") do
      config_for("android", "1.1.5")
    end
    expect(response).to have_http_status(:ok)
    expect(queries.grep(/"users"/)).to be_empty
  end

  it "never sends auth headers back, even to a signed-in app, and does no per-user work" do
    headers = auth_headers_for(create(:user)).merge("X-App-Platform" => "android", "X-App-Version" => "1.1.5")
    queries = []
    ActiveSupport::Notifications.subscribed(->(*, p) { queries << p[:sql] }, "sql.active_record") do
      get "/api/v1/app_config", headers: headers
    end
    expect(response).to have_http_status(:ok)
    expect(response.headers.keys.map(&:downcase)).not_to include("access-token", "client", "uid", "expiry")
    expect(response.headers["Cache-Control"]).not_to include("public")
    expect(queries.grep(/"users"/)).to be_empty
  end

  # OFFLINE §8.6: the rules the phone checks before a listing is queued — the
  # model's own limits, so the phone and the server never drift.
  it "carries the listing rules, from the model's own limits" do
    get "/api/v1/app_config"
    rules = JSON.parse(response.body)["listing_rules"]
    expect(rules).to include(
      "title_max" => Listing::MAX_TITLE_LENGTH,
      "description_max" => Listing::MAX_DESCRIPTION_LENGTH,
      "quantity_max" => Listing::MAX_QUANTITY,
      "max_photos" => Listing::MAX_IMAGES,
      "photo_required_to_publish" => true,
      "video_max_seconds" => HasVideo::MAX_VIDEO_DURATION_S,
      "video_max_bytes" => HasVideo::MAX_VIDEO_SIZE
    )
    expect(rules["price_max"].to_d).to eq(Listing::MAX_PRICE.to_d)
  end

  describe "features.image_search" do
    it "is true when this server has the image model", :image_search do
      get "/api/v1/app_config"
      expect(response.parsed_body.dig("features", "image_search")).to be true
    end

    it "is false without the model" do
      allow(ImageSearch::Embedder).to receive(:available?).and_return(false)
      get "/api/v1/app_config"
      expect(response.parsed_body.dig("features", "image_search")).to be false
    end

    it "is false with the kill switch IMAGE_SEARCH_ENABLED=0, model or not", :image_search do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("IMAGE_SEARCH_ENABLED").and_return("0")
      get "/api/v1/app_config"
      expect(response.parsed_body.dig("features", "image_search")).to be false
    end
  end
end
