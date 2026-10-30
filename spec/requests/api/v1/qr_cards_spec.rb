require "swagger_helper"

# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.5): the printable QR card of a shop
# or a listing. Public data, like the pages it points to: no sign-in, cached (ETag + Cache-Control),
# throttled by IP, 404 for what is not public (a closed / suspended shop, a listing that is not live).
RSpec.describe "QR cards", type: :request do
  let(:shop) { create(:shop) }
  let(:listing) { create(:listing, :active, :with_image) }

  around do |example|
    previous = ENV.fetch("PUBLIC_SHARE_BASE_URL", nil)
    ENV["PUBLIC_SHARE_BASE_URL"] = "https://hatiwal.com"
    example.run
  ensure
    ENV["PUBLIC_SHARE_BASE_URL"] = previous
  end

  path "/api/v1/shops/{id}/qr_card.{format}" do
    get "a shop's printable QR card (PNG or PDF, A6)" do
      tags "Share"
      description "Public. lang: en | ps | fa (anything else: en). The QR opens https://hatiwal.com/s/<id>?lang=<lang>&src=qr " \
                  "(the app when installed, the web otherwise). 404 when the shop is closed, suspended or pending."
      produces "image/png", "application/pdf"
      parameter name: :id, in: :path, type: :integer
      parameter name: :format, in: :path, type: :string, enum: %w[png pdf]
      parameter name: :lang, in: :query, type: :string, required: false
      let(:id) { shop.id }
      let(:format) { "png" }
      let(:lang) { "ps" }

      response "200", "the PNG card" do
        run_test! do
          expect(response.media_type).to eq("image/png")
          expect(Vips::Image.new_from_buffer(response.body, "").width).to eq(1240)
          expect(response.headers["Cache-Control"]).to include("public", "max-age=")
          expect(response.headers["ETag"]).to be_present
        end
      end

      response "200", "the PDF card" do
        let(:format) { "pdf" }

        run_test! do
          expect(response.media_type).to eq("application/pdf")
          expect(response.body).to start_with("%PDF-")
          expect(response.headers["Content-Disposition"]).to include("hatiwal-shop-#{shop.id}-ps.pdf")
        end
      end

      response "404", "a closed shop" do
        before { shop.update_columns(status: Shop.statuses[:closed]) }

        run_test!
      end

      response "404", "a suspended shop" do
        before { shop.update_columns(status: Shop.statuses[:suspended]) }

        run_test!
      end
    end
  end

  path "/api/v1/listings/{id}/qr_card.{format}" do
    get "a listing's printable QR card (PNG or PDF, A6)" do
      tags "Share"
      description "Public. The QR opens https://hatiwal.com/l/<id>?lang=<lang>&src=qr. 404 unless the listing is live and public."
      produces "image/png", "application/pdf"
      parameter name: :id, in: :path, type: :integer
      parameter name: :format, in: :path, type: :string, enum: %w[png pdf]
      parameter name: :lang, in: :query, type: :string, required: false
      let(:id) { listing.id }
      let(:format) { "png" }
      let(:lang) { "fa" }

      response "200", "the PNG card" do
        run_test! { expect(response.media_type).to eq("image/png") }
      end

      { "a draft" => :draft, "a sold listing" => :sold }.each do |what, status|
        response "404", what do
          before { listing.update_columns(status: Listing.statuses[status]) }

          run_test!
        end
      end

      response "404", "a listing an admin removed" do
        before { listing.update_columns(removed_at: Time.current) }

        run_test!
      end
    end
  end

  describe "caching" do
    it "answers 304 to the same ETag, and a new card once the shop changes" do
      get "/api/v1/shops/#{shop.id}/qr_card.png", params: { lang: "en" }
      etag = response.headers["ETag"]

      get "/api/v1/shops/#{shop.id}/qr_card.png", params: { lang: "en" }, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)

      get "/api/v1/shops/#{shop.id}/qr_card.png", params: { lang: "ps" }, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)

      shop.update!(name: "Renamed shop")
      get "/api/v1/shops/#{shop.id}/qr_card.png", params: { lang: "en" }, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "is throttled by IP, generously (carrier-grade NAT): #{Api::V1::QrCardsController::PER_IP_PER_HOUR} an hour" do
      get "/api/v1/shops/#{shop.id}/qr_card.png"
      etag = response.headers["ETag"]
      statuses = Array.new(Api::V1::QrCardsController::PER_IP_PER_HOUR) do
        get "/api/v1/shops/#{shop.id}/qr_card.png", headers: { "If-None-Match" => etag }
        response.status
      end

      expect(statuses.last).to eq(429)
      expect(statuses.first(Api::V1::QrCardsController::PER_IP_PER_HOUR - 1)).to all(eq(304))
    end
  end

  describe "share visits (?src=) in our own log" do
    before { allow(Rails.logger).to receive(:info).and_call_original }

    it "the listing page counts a visit that came from a share" do
      get "/api/v1/listings/#{listing.id}", params: { src: "wa", lang: "ps" }

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:info).with("[share_visit] src=wa kind=listing id=#{listing.id} lang=ps")
    end

    it "the shop page too" do
      get "/api/v1/shops/#{shop.id}", params: { src: "qr" }

      expect(Rails.logger).to have_received(:info).with("[share_visit] src=qr kind=shop id=#{shop.id} lang=")
    end
  end

  describe "the share image (OG card, 1200 × 630)" do
    it "is on the listing detail and on the shop" do
      listing.images.attachments.first.blob.analyze # variants need an analysed photo (PublicImageUrl.processable?)
      get "/api/v1/listings/#{listing.id}"
      expect(JSON.parse(response.body).dig("listing", "image_share_url")).to include("/rails/active_storage/representations/")

      get "/api/v1/shops/#{shop.id}"
      expect(JSON.parse(response.body).dig("shop")).to have_key("share_image_url")
    end
  end
end
