require "swagger_helper"

# VID (1.1.9, docs/LISTING_VIDEO.md) — one optional video per listing, uploaded
# apart from the listing save.
RSpec.describe "Api::V1::My::ListingVideos", type: :request do
  let(:owner)   { create(:user) }
  let(:listing) { create(:listing, :active, :with_image, user: owner) }
  let(:headers) { auth_headers_for(owner) }
  let(:mp4)     { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4") }
  let(:jpg)     { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }

  path "/api/v1/my/listings/{listing_id}/video" do
    parameter name: :listing_id, in: :path, type: :integer
    parameter name: :"access-token", in: :header, type: :string, required: true
    parameter name: :client,         in: :header, type: :string, required: true
    parameter name: :uid,            in: :header, type: :string, required: true
    let(:listing_id)     { listing.id }
    let(:"access-token") { headers["access-token"] }
    let(:client)         { headers["client"] }
    let(:uid)            { headers["uid"] }

    put "set (or replace) the listing's video" do
      tags "Listings"
      description "Multipart. `video`: MP4 or QuickTime, at most 25 MB and 60 s (the apps compress to ~720p and " \
                  "trim before upload). `poster`: an image frame from the client, optional. `duration_s`: the " \
                  "client's measurement. Replaces any previous video. Only whoever manages the listing (the " \
                  "poster or a shop member); not on a sold or deleted listing."
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :video,      in: :formData, type: :string, format: :binary, required: true
      parameter name: :poster,     in: :formData, type: :string, format: :binary, required: false
      parameter name: :duration_s, in: :formData, type: :number, required: false

      response "200", "attached; the listing comes back with its video" do
        let(:video)      { mp4 }
        let(:poster)     { jpg }
        let(:duration_s) { 2.4 }

        run_test! do
          body = JSON.parse(response.body)["listing"]
          expect(body["has_video"]).to be(true)
          expect(body["video_url"]).to be_present
          expect(body["video_poster_url"]).to be_present
          expect(body["video_duration_s"]).to eq(2)
          expect(listing.reload.video.blob.content_type).to eq("video/mp4")
        end
      end

      response "422", "not a video" do
        let(:video)      { jpg }
        let(:poster)     { jpg }
        let(:duration_s) { 2 }

        run_test! do
          expect(JSON.parse(response.body)["errors"].join).to match(/unsupported file type/)
          expect(listing.reload.video).not_to be_attached
        end
      end
    end

    delete "remove the listing's video" do
      tags "Listings"
      produces "application/json"
      security [ { bearer: [] } ]

      response "200", "removed; the photos stay" do
        let(:listing) { create(:listing, :active, :with_image, :with_video, user: owner) }

        run_test! do
          body = JSON.parse(response.body)["listing"]
          expect(body["has_video"]).to be(false)
          expect(body["video_url"]).to be_nil
          expect(listing.reload.video).not_to be_attached
          expect(listing.images).to be_attached
        end
      end
    end
  end

  def put_video(params, as: headers, id: listing.id)
    put "/api/v1/my/listings/#{id}/video", params: params, headers: as
  end

  it "requires authentication" do
    put "/api/v1/my/listings/#{listing.id}/video", params: { video: mp4 }
    expect(response).to have_http_status(:unauthorized)
  end

  it "is 404 for someone else's listing" do
    put_video({ video: mp4 }, as: auth_headers_for(create(:user)))
    expect(response).to have_http_status(:not_found)
    expect(listing.reload.video).not_to be_attached
  end

  it "lets a member of the listing's shop set it" do
    shop = create(:shop, owner: owner)
    shop_listing = create(:listing, :active, :with_image, user: owner, shop: shop)
    staff = create(:shop_member, shop: shop, role: :staff).user

    put_video({ video: mp4 }, as: auth_headers_for(staff), id: shop_listing.id)

    expect(response).to have_http_status(:ok)
    expect(shop_listing.reload.video).to be_attached
  end

  it "is refused on a sold listing" do
    listing.update_columns(status: Listing.statuses[:sold], sold_at: Time.current)
    put_video({ video: mp4 })
    expect(response).to have_http_status(:forbidden)
  end

  it "works on a draft, so the seller can add it before publishing" do
    draft = create(:listing, :draft, user: owner)
    put_video({ video: mp4 }, id: draft.id)
    expect(response).to have_http_status(:ok)
  end

  it "refuses a clip longer than 60 s" do
    put_video({ video: mp4, duration_s: 95 })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"].join).to match(/60 seconds/)
    expect(ActiveStorage::Blob.where(content_type: "video/mp4")).to be_empty
  end

  it "refuses a file over 25 MB and keeps nothing" do
    big = Tempfile.new([ "big", ".mp4" ])
    big.binmode
    big.write(File.binread(Rails.root.join("spec/fixtures/files/test_video.mp4")))
    big.write("\0" * (Listing::MAX_VIDEO_SIZE + 1))
    big.flush

    put_video({ video: Rack::Test::UploadedFile.new(big.path, "video/mp4") })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["errors"].join).to match(/larger than the 25 MB limit/)
    expect(listing.reload.video).not_to be_attached
  ensure
    big&.close!
  end

  it "refuses a signed id instead of a file (no borrowing someone else's blob)" do
    other = create(:listing, :active, :with_video)
    put_video({ video: other.video.blob.signed_id })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["code"]).to eq("invalid_upload")
  end

  it "replaces the previous video and its poster" do
    listing = create(:listing, :active, :with_image, :with_video, user: owner)
    old_keys = [ listing.video.blob.key, listing.video_poster.blob.key ]

    perform_enqueued_jobs { put_video({ video: mp4 }, id: listing.id) }

    expect(response).to have_http_status(:ok)
    listing.reload
    expect(listing.video).to be_attached
    expect(listing.video_poster).not_to be_attached # the new upload came without one
    old_keys.each { |key| expect(ActiveStorage::Blob.service.exist?(key)).to be(false) }
  end

  it "keeps the listing's photos and status untouched" do
    put_video({ video: mp4, poster: jpg })
    listing.reload
    expect(listing).to be_active
    expect(listing.images.count).to eq(1)
  end

  describe "old clients" do
    # A 1.1.7/1.1.8 app never sends `video` and must see exactly what it saw:
    # the new keys are additions only, and nothing it reads changed.
    it "a listing save without a video is unchanged, and the detail only gains keys" do
      put "/api/v1/my/listings/#{listing.id}", params: { listing: { title: "Old app edit" } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["listing"]
      expect(body).to include("title" => "Old app edit", "has_video" => false, "video_url" => nil,
                              "video_poster_url" => nil, "video_duration_s" => nil)
      expect(body["images"].size).to eq(1)
    end
  end

  describe "where the video shows" do
    let!(:with_video) { create(:listing, :active, :with_image, :with_video) }
    let!(:plain)      { create(:listing, :active, :with_image) }

    it "cards carry has_video only (no URLs in the feed)" do
      get "/api/v1/listings", headers: auth_headers_for(create(:user))
      cards = JSON.parse(response.body)["listings"].index_by { |l| l["id"] }
      expect(cards[with_video.id]["has_video"]).to be(true)
      expect(cards[plain.id]["has_video"]).to be(false)
      expect(cards[with_video.id]).not_to have_key("video_url")
    end

    it "the public detail carries the URLs; the video URL serves the file" do
      get "/api/v1/listings/#{with_video.id}", headers: auth_headers_for(create(:user))
      body = JSON.parse(response.body)["listing"]
      expect(body).to include("has_video" => true, "video_duration_s" => 2)

      get URI(body["video_url"]).path
      expect(response).to have_http_status(:redirect)
      get response.location, headers: { "Range" => "bytes=0-99" }
      expect(response).to have_http_status(:partial_content)
      expect(response.body.bytesize).to eq(100)
    end
  end

  describe "DELETE" do
    it "is 404 for someone else's listing" do
      listing = create(:listing, :active, :with_video)
      delete "/api/v1/my/listings/#{listing.id}/video", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(listing.reload.video).to be_attached
    end

    it "works on a sold listing too" do
      listing = create(:listing, :sold, :with_video, user: owner)
      delete "/api/v1/my/listings/#{listing.id}/video", headers: headers
      expect(response).to have_http_status(:ok)
      expect(listing.reload.video).not_to be_attached
    end
  end
end
