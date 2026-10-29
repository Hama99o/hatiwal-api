require "swagger_helper"

# Search by image (docs/IMAGE_SEARCH.md). The embedder is stubbed: the photo's
# vector is chosen per example, so the expected ranking is exact. The real
# model is covered by spec/services/image_search/embedder_spec.rb.
RSpec.describe "Api::V1::Listings image search", :image_search, type: :request do
  let(:photo_path) { Rails.root.join("spec/fixtures/files/test_image.jpg") }
  let(:photo)      { Rack::Test::UploadedFile.new(photo_path, "image/jpeg") }
  let(:category)   { create(:category) }

  before { allow(ImageSearch::Embedder).to receive(:embed).and_return(fake_vector(0)) }

  def listing_with_vector(vector, trait = :active, **attrs)
    listing = create(:listing, trait, :with_image, category: category, **attrs)
    embed_photo!(listing, vector)
    listing
  end

  def search(params = { image: photo }, headers: {})
    post "/api/v1/listings/image_search", params: params, headers: headers
  end

  def ids = response.parsed_body["listings"].map { |l| l["id"] }

  path "/api/v1/listings/image_search" do
    post "search listings by photo" do
      tags "Listings"
      description "Search by image (docs/IMAGE_SEARCH.md). ONE photo (jpeg/png/webp/gif/heic/heif/avif, checked by its " \
                  "bytes, 10 MB max); it is embedded in memory and never stored. Returns browsable listings whose " \
                  "photos look similar, best first, as the feed's :list cards, paginated like the feed. Public " \
                  "(a signed-in viewer's hidden listings and blocked sellers are left out). Limits: 30 per 10 min " \
                  "per user (a guest: per IP) and 120 per 10 min per IP, then 429. 503 code image_search_unavailable " \
                  "when the server has no model (GET /app_config features.image_search is then false)."
      consumes "multipart/form-data"
      produces "application/json"
      parameter name: :image, in: :formData, schema: { type: :string, format: :binary }, required: true
      parameter name: :category_id, in: :formData, schema: { type: :integer }, required: false,
                description: "only this category (and its subcategories)"
      parameter name: :"page[number]", in: :formData, schema: { type: :integer }, required: false
      parameter name: :"page[size]", in: :formData, schema: { type: :integer }, required: false

      response "200", "similar listings, best match first" do
        schema type: :object,
               properties: {
                 listings: { type: :array, items: { type: :object } },
                 meta: { type: :object, properties: { pagination: { type: :object } } }
               },
               required: %w[listings meta]
        let(:image) { photo }
        let!(:match) { listing_with_vector(fake_vector(0)) }

        run_test! do
          expect(ids).to eq([ match.id ])
          expect(response.parsed_body["listings"].first.keys).to include("thumbnail_url", "price", "seller")
        end
      end

      response "422", "not a photo (code invalid_image)" do
        let(:image) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.zip"), "image/jpeg") }

        run_test! { expect(response.parsed_body["code"]).to eq("invalid_image") }
      end
    end
  end

  it "ranks the listings by similarity, best first" do
    far  = listing_with_vector(fake_vector(0, other: 1, mix: 0.4))
    near = listing_with_vector(fake_vector(0, other: 1, mix: 0.05))

    search
    expect(response).to have_http_status(:ok)
    expect(ids).to eq([ near.id, far.id ])
  end

  it "answers an empty page when nothing is close enough (the minimum score)" do
    listing_with_vector(fake_vector(1))

    search
    expect(response).to have_http_status(:ok)
    expect(ids).to eq([])
    expect(response.parsed_body.dig("meta", "pagination", "total_count")).to eq(0)
  end

  it "answers an empty page, not an error, for a blank photo (a covered lens)" do
    listing_with_vector(fake_vector(0))
    allow(ImageSearch::Embedder).to receive(:embed).and_raise(ImageSearch::Embedder::PlainImage, "plain image")

    search
    expect(response).to have_http_status(:ok)
    expect(ids).to eq([])
  end

  it "only ever returns browsable listings: never draft, sold, expired or removed ones" do
    live = listing_with_vector(fake_vector(0))
    reserved = listing_with_vector(fake_vector(0), :reserved)
    listing_with_vector(fake_vector(0), :draft)
    listing_with_vector(fake_vector(0), :sold)
    listing_with_vector(fake_vector(0), :expired)
    listing_with_vector(fake_vector(0)).update_columns(removed_at: Time.current)

    search
    expect(ids).to contain_exactly(live.id, reserved.id)
  end

  it "leaves out a signed-in viewer's hidden listings and blocked sellers" do
    viewer = create(:user)
    hidden = listing_with_vector(fake_vector(0))
    blocked = listing_with_vector(fake_vector(0))
    shown = listing_with_vector(fake_vector(0))
    create(:hidden_listing, user: viewer, listing: hidden)
    create(:block, blocker: viewer, blocked: blocked.user)

    search(headers: auth_headers_for(viewer))
    expect(ids).to eq([ shown.id ])
  end

  it "filters by category" do
    other = listing_with_vector(fake_vector(0), category: create(:category))
    mine = listing_with_vector(fake_vector(0))

    search({ image: photo, category_id: category.id })
    expect(ids).to eq([ mine.id ])
    expect(other).to be_persisted
  end

  it "paginates" do
    3.times { |i| listing_with_vector(fake_vector(0, other: 1, mix: 0.01 * i)) }

    search({ image: photo, page: { number: 2, size: 2 } })
    expect(ids.size).to eq(1)
    expect(response.parsed_body.dig("meta", "pagination")).to include("current_page" => 2, "total_count" => 3)
  end

  it "never stores the photo it searched with" do
    listing_with_vector(fake_vector(0))

    expect { search }.not_to change { [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count ] }
  end

  it "refuses a request without a photo" do
    search({})
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("image_missing")
  end

  it "refuses a file whose BYTES are not a photo, whatever its name and declared type" do
    search({ image: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.zip"), "image/jpeg", original_filename: "x.jpg") })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_image")
    expect(ImageSearch::Embedder).not_to have_received(:embed)
  end

  it "refuses a photo over 10 MB" do
    big = Tempfile.new([ "big", ".jpg" ])
    big.binmode
    big.write(File.binread(photo_path))
    big.write("\0" * (Listing::MAX_IMAGE_SIZE + 1))
    big.flush

    search({ image: Rack::Test::UploadedFile.new(big.path, "image/jpeg") })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("image_too_large")
  ensure
    big&.close!
  end

  it "answers 422 invalid_image when the decoder cannot read the photo" do
    allow(ImageSearch::Embedder).to receive(:embed).and_raise(ImageSearch::Embedder::InvalidImage, "truncated")

    search
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_image")
  end

  it "answers 503 image_search_unavailable when the server has no model" do
    allow(ImageSearch::Embedder).to receive(:available?).and_return(false)

    search
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["code"]).to eq("image_search_unavailable")
  end

  it "limits a signed-in user to 30 searches per 10 minutes" do
    headers = auth_headers_for(create(:user))
    30.times { search(headers: headers) }
    expect(response).to have_http_status(:ok)

    search(headers: headers)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["error"]).to eq("rate_limited")
  end

  it "limits a guest per IP" do
    30.times { search }
    search
    expect(response).to have_http_status(:too_many_requests)
  end
end
