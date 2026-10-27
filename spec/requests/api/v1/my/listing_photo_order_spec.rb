require "rails_helper"

# OFFLINE phase 0 (docs/OFFLINE_MODE.md §2.5): the edit form reorders photos,
# and the order used to be dropped on the way out — PUT had no order field and
# the photos came back in upload order. `image_order[]` carries it: the photos'
# signed ids, plus "new:<n>" for a photo uploaded in the same request.
RSpec.describe "My listings — photo order", type: :request do
  let(:seller)  { create(:user) }
  let(:headers) { auth_headers_for(seller) }
  let(:listing) { create(:listing, user: seller) }

  def real_photo(name = "new.jpg")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg",
                                 original_filename: name)
  end

  def attach(name)
    listing.images.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: name,
                          content_type: "image/jpeg")
  end

  def signed_id_of(name)
    listing.reload.images.find { |a| a.blob.filename.to_s == name }.blob.signed_id
  end

  def names_in_order(body)
    ids = body["listing"]["image_attachments"].pluck("id")
    ids.map { |sid| ActiveStorage::Blob.find_signed(sid).filename.to_s }
  end

  def put_listing(params)
    put "/api/v1/my/listings/#{listing.id}", params: { listing: { title: "Same" }.merge(params) }, headers: headers
  end

  before do
    attach("a.jpg")
    attach("b.jpg")
    attach("c.jpg")
  end

  it "keeps upload order when no image_order is sent (a 1.1.8 app)" do
    put_listing({})

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[a.jpg b.jpg c.jpg])
  end

  it "stores the seller's order and every photo reader follows it" do
    put_listing(image_order: [ signed_id_of("c.jpg"), signed_id_of("a.jpg"), signed_id_of("b.jpg") ])

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(names_in_order(body)).to eq(%w[c.jpg a.jpg b.jpg])

    reloaded = Listing.find(listing.id)
    expect(reloaded.ordered_images.map { |a| a.blob.filename.to_s }).to eq(%w[c.jpg a.jpg b.jpg])
    # The URL lists (built only inside a request) follow the same order.
    expect(body["listing"]["images"].map { |u| File.basename(u) }).to eq(%w[c.jpg a.jpg b.jpg])
  end

  it "keeps the order on the next read (the feed and the detail)" do
    put_listing(image_order: [ signed_id_of("b.jpg"), signed_id_of("c.jpg"), signed_id_of("a.jpg") ])
    listing.update!(status: :active, published_at: Time.current)

    get "/api/v1/listings/#{listing.id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[b.jpg c.jpg a.jpg])
  end

  it "places a photo uploaded in the same save with new:<n>" do
    put_listing(images: [ real_photo("n0.jpg"), real_photo("n1.jpg") ],
                image_order: [ "new:1", signed_id_of("b.jpg"), "new:0", signed_id_of("a.jpg"), signed_id_of("c.jpg") ])

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[n1.jpg b.jpg n0.jpg a.jpg c.jpg])
  end

  it "puts a photo the list leaves out after the listed ones, and never deletes it" do
    put_listing(image_order: [ signed_id_of("c.jpg") ])

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[c.jpg a.jpg b.jpg])
  end

  it "ignores another listing's photo, a garbage token and an out-of-range new:<n>" do
    other = create(:listing, user: seller)
    other.images.attach(io: StringIO.new("x"), filename: "other.jpg", content_type: "image/jpeg")

    put_listing(image_order: [ other.images.first.blob.signed_id, "nonsense", "new:7", signed_id_of("b.jpg") ])

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[b.jpg a.jpg c.jpg])
    expect(other.reload.images.first.blob.metadata["position"]).to be_nil
  end

  it "combines with removed_image_ids" do
    removed = signed_id_of("a.jpg")
    put_listing(removed_image_ids: [ removed ], image_order: [ signed_id_of("c.jpg"), removed, signed_id_of("b.jpg") ])

    expect(response).to have_http_status(:ok)
    expect(names_in_order(JSON.parse(response.body))).to eq(%w[c.jpg b.jpg])
  end

  it "makes the first photo in the order the card thumbnail" do
    put_listing(image_order: [ signed_id_of("c.jpg"), signed_id_of("a.jpg"), signed_id_of("b.jpg") ])

    get "/api/v1/my/listings", headers: headers

    row = JSON.parse(response.body)["listings"].find { |l| l["id"] == listing.id }
    expect(File.basename(row["thumbnail_url"])).to eq("c.jpg")
  end

  it "copies the photos in the seller's order when the listing is duplicated" do
    put_listing(image_order: [ signed_id_of("c.jpg"), signed_id_of("b.jpg"), signed_id_of("a.jpg") ])

    copy = Listings::DuplicateService.new(listing: Listing.find(listing.id), actor: seller, shop_id: nil).call
    expect(copy.ordered_images.map { |a| a.blob.filename.to_s }).to eq(%w[c.jpg b.jpg a.jpg])
  end

  # B12 (2026-10-27): on CREATE the cover the seller chose was lost — the app
  # appended photos as their compression finished, and the API had no order
  # field on POST. Now POST takes image_order too ("new:<n>" only: every photo
  # is new), and the app sends it.
  describe "POST /api/v1/my/listings — image_order on create" do
    let(:category) { create(:category) }

    def post_listing(extra)
      post "/api/v1/my/listings",
           params: { listing: { title: "Toyota Corolla 2003", price: 320_000, currency: "AFN",
                                category_id: category.id, location: "Kabul" }.merge(extra) },
           headers: headers
    end

    it "the 2nd photo chosen as cover comes back first, the others in the seller's order" do
      post_listing(images: [ real_photo("p0.jpg"), real_photo("p1.jpg"), real_photo("p2.jpg") ],
                   image_order: %w[new:1 new:0 new:2])

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(names_in_order(body)).to eq(%w[p1.jpg p0.jpg p2.jpg])
      # The cover everywhere (thumbnail_url, the feed card) is ordered_images.first.
      expect(Listing.find(body["listing"]["id"]).ordered_images.first.blob.filename.to_s).to eq("p1.jpg")
    end

    it "keeps upload order when no image_order is sent (a 1.1.x app)" do
      post_listing(images: [ real_photo("p0.jpg"), real_photo("p1.jpg"), real_photo("p2.jpg") ])

      expect(response).to have_http_status(:created)
      expect(names_in_order(JSON.parse(response.body))).to eq(%w[p0.jpg p1.jpg p2.jpg])
    end

    it "ignores garbage and out-of-range tokens on create" do
      post_listing(images: [ real_photo("p0.jpg"), real_photo("p1.jpg") ], image_order: %w[new:9 junk new:1])

      expect(response).to have_http_status(:created)
      expect(names_in_order(JSON.parse(response.body))).to eq(%w[p1.jpg p0.jpg])
    end
  end
end
