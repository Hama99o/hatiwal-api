require "swagger_helper"

# SHOP-MEDIA (docs/SHOP_MEDIA.md): a shop's video (the listing video's twin)
# and its gallery of up to 5 photos.
RSpec.describe "Shop photos + video", type: :request do
  let(:shop)    { create(:shop) }
  let(:owner)   { shop.owner }
  let(:headers) { auth_headers_for(owner) }
  let(:mp4)     { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_video.mp4"), "video/mp4") }
  def jpg = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg")

  path "/api/v1/shops/{shop_id}/video" do
    parameter name: :shop_id, in: :path, type: :integer
    parameter name: :"access-token", in: :header, type: :string, required: true
    parameter name: :client,         in: :header, type: :string, required: true
    parameter name: :uid,            in: :header, type: :string, required: true
    let(:shop_id)        { shop.id }
    let(:"access-token") { headers["access-token"] }
    let(:client)         { headers["client"] }
    let(:uid)            { headers["uid"] }

    put "set (or replace) the shop's video" do
      tags "Shops"
      description "The listing video's rules (PUT /my/listings/:id/video): multipart `video` (MP4/QuickTime, " \
                  "≤ 25 MB, ≤ 60 s), optional `poster` image and `duration_s`. The shop's owner or a manager; " \
                  "never a closed shop. Answers the shop (owner view)."
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :video,      in: :formData, type: :string, format: :binary, required: true
      parameter name: :poster,     in: :formData, type: :string, format: :binary, required: false
      parameter name: :duration_s, in: :formData, type: :number, required: false

      response "200", "attached" do
        let(:video)      { mp4 }
        let(:poster)     { jpg }
        let(:duration_s) { 2 }

        run_test! do
          body = JSON.parse(response.body)["shop"]
          expect(body).to include("has_video" => true, "video_duration_s" => 2)
          expect(body["video_url"]).to be_present
          expect(body["video_poster_url"]).to be_present
        end
      end
    end

    delete "remove the shop's video" do
      tags "Shops"
      produces "application/json"
      security [ { bearer: [] } ]

      response "200", "removed" do
        let(:shop) { create(:shop, :with_video) }

        run_test! { expect(JSON.parse(response.body)["shop"]).to include("has_video" => false, "video_url" => nil) }
      end
    end
  end

  path "/api/v1/shops/{shop_id}/gallery" do
    parameter name: :shop_id, in: :path, type: :integer
    parameter name: :"access-token", in: :header, type: :string, required: true
    parameter name: :client,         in: :header, type: :string, required: true
    parameter name: :uid,            in: :header, type: :string, required: true
    let(:shop_id)        { shop.id }
    let(:"access-token") { headers["access-token"] }
    let(:client)         { headers["client"] }
    let(:uid)            { headers["uid"] }

    put "add, remove and reorder the shop's photos (up to 5)" do
      tags "Shops"
      description "Multipart. `gallery[keep_ids][]`: the shop's own photo ids (`gallery_photos[].id`) in the order " \
                  "to show; `gallery[photos][]`: new image files, appended. A photo left out of keep_ids is deleted. " \
                  "More than 5 → 422."
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :gallery, in: :formData, schema: {
        type: :object,
        properties: {
          keep_ids: { type: :array, items: { type: :string }, description: "the shop's own photo ids, in order" },
          photos: { type: :array, items: { type: :string, format: :binary }, description: "new photos, appended" }
        }
      }

      response "200", "the gallery, in order" do
        let(:gallery) { { photos: [ jpg, jpg ] } }

        run_test! do
          photos = JSON.parse(response.body)["shop"]["gallery_photos"]
          expect(photos.size).to eq(2)
          expect(photos.first.keys).to contain_exactly("id", "url", "medium_url", "thumb_url")
        end
      end
    end
  end

  def put_video(params, as: headers, id: shop.id) = put("/api/v1/shops/#{id}/video", params: params, headers: as)
  def put_gallery(params, as: headers, id: shop.id) = put("/api/v1/shops/#{id}/gallery", params: params, headers: as)

  it "lets a manager set it, refuses staff and strangers" do
    manager = create(:shop_member, shop: shop, role: :manager).user
    staff = create(:shop_member, shop: shop, role: :staff).user

    put_video({ video: mp4 }, as: auth_headers_for(manager))
    expect(response).to have_http_status(:ok)

    put_video({ video: mp4 }, as: auth_headers_for(staff))
    expect(response).to have_http_status(:forbidden)

    put_gallery({ gallery: { photos: [ jpg ] } }, as: auth_headers_for(create(:user)))
    expect(response).to have_http_status(:forbidden)
  end

  it "requires authentication" do
    put "/api/v1/shops/#{shop.id}/video", params: { video: mp4 }
    expect(response).to have_http_status(:unauthorized)
  end

  it "is refused on a closed shop" do
    shop.close!
    put_video({ video: mp4 })
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses a sixth photo with a 422" do
    put_gallery({ gallery: { photos: Array.new(6) { jpg } } })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(shop.reload.gallery_photos).not_to be_attached
  end

  it "refuses a signed id posing as an upload" do
    other = create(:shop, :with_video)
    put_video({ video: other.video.blob.signed_id })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["code"]).to eq("invalid_upload")
  end

  it "the public shop page carries the photos + video; old clients only gain keys" do
    shop = create(:shop, :with_video, :with_gallery)
    get "/api/v1/shops/#{shop.id}"
    body = JSON.parse(response.body)["shop"]
    expect(body).to include("has_video" => true, "video_duration_s" => 2)
    expect(body["gallery_photos"].pluck("url").size).to eq(2)
    # Everything a 1.1.7 app reads is still there, unchanged in kind.
    expect(body).to include("id", "name", "logo_url", "cover_url", "description", "listings_count")
  end

  it "a shop without media answers empty / false / null" do
    get "/api/v1/shops/#{shop.id}"
    expect(JSON.parse(response.body)["shop"]).to include("has_video" => false, "video_url" => nil, "gallery_photos" => [])
  end
end
