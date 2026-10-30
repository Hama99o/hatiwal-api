require "swagger_helper"

# Sell with a photo (docs/SELL_WITH_PHOTO.md). The photo's embedding and the
# scorer are stubbed here (both have their own service specs): these examples
# pin the HTTP contract, the photo checks, the limits and the outcome log.
RSpec.describe "Api::V1::My::CategorySuggestions", :image_search, type: :request do
  let(:user)       { create(:user) }
  let(:headers)    { auth_headers_for(user) }
  let(:photo)      { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }
  let(:phones)     { create(:category, slug: "phones", parent: create(:category, slug: "electronics")) }
  let(:suggestion) { CategorySuggestion::Result.new(category_id: phones.id, parent_id: phones.parent_id, confidence: 0.62) }

  let(:"access-token") { headers["access-token"] }
  let(:client)         { headers["client"] }
  let(:uid)            { headers["uid"] }

  before do
    allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(true)
    allow(ImageSearch::Embedder).to receive(:embed).and_return(fake_vector(0))
    allow(CategorySuggestion).to receive(:call).and_return(suggestion)
    allow(Rails.logger).to receive(:info).and_call_original
  end

  def suggest(params = { image: photo }, as: headers)
    post "/api/v1/my/listings/category_suggestion", params: params, headers: as
  end

  def report(params, as: headers)
    post "/api/v1/my/listings/category_suggestion/outcome", params: params, headers: as
  end

  def logged(pattern) = have_received(:info).with(a_string_matching(pattern))

  path "/api/v1/my/listings/category_suggestion" do
    post "suggest a category for the first photo of a new listing" do
      tags "My Listings"
      description "Sell with a photo (docs/SELL_WITH_PHOTO.md). ONE photo, checked like a listing photo (type by its " \
                  "bytes, 10 MB max), embedded in memory and never stored. Answers the most likely category's id " \
                  "(and its parent's) with the model's confidence, or 204 when it is not sure. No text: the apps " \
                  "show the category's own localized name. Signed in only; 30 per 10 min per user, 120 per IP. " \
                  "503 code category_suggestion_unavailable when the server cannot suggest (GET /app_config " \
                  "features.category_suggestion is then false)."
      consumes "multipart/form-data"
      produces "application/json"
      parameter name: :image, in: :formData, schema: { type: :string, format: :binary }, required: true
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      response "200", "a suggestion" do
        schema type: :object,
               properties: {
                 category_id: { type: :integer },
                 parent_id: { type: :integer, nullable: true },
                 confidence: { type: :number, description: "0..1; only answered at 0.40 or more" }
               },
               required: %w[category_id parent_id confidence]
        let(:image) { photo }

        run_test! do
          expect(response.parsed_body).to eq("category_id" => phones.id, "parent_id" => phones.parent_id, "confidence" => 0.62)
        end
      end

      response "204", "not sure: no suggestion" do
        before { allow(CategorySuggestion).to receive(:call).and_return(nil) }

        let(:image) { photo }

        run_test! { expect(response.body).to be_empty }
      end

      response "422", "not a photo (code invalid_image)" do
        let(:image) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.zip"), "image/jpeg") }

        run_test! { expect(response.parsed_body["code"]).to eq("invalid_image") }
      end
    end
  end

  path "/api/v1/my/listings/category_suggestion/outcome" do
    post "report what the seller did with a suggestion (for tuning; nothing stored)" do
      tags "My Listings"
      description "Writes one log line (docs/SELL_WITH_PHOTO.md §3): outcome accepted | dismissed | replaced " \
                  "(the seller picked another category while it was shown), the suggested category_id and " \
                  "confidence. No photo, no user content. 60 per 10 min per user."
      consumes "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: { outcome: { type: :string, enum: CategorySuggestion::OUTCOMES },
                      category_id: { type: :integer }, confidence: { type: :number } },
        required: %w[outcome category_id]
      }
      parameter name: :"access-token", in: :header, type: :string, required: false
      parameter name: :client,         in: :header, type: :string, required: false
      parameter name: :uid,            in: :header, type: :string, required: false

      response "204", "logged" do
        let(:body) { { outcome: "accepted", category_id: phones.id, confidence: 0.62 } }

        run_test! { expect(Rails.logger).to logged(/category_suggestion event=accepted category_id=#{phones.id} confidence=0.62/) }
      end

      response "422", "an unknown outcome (code invalid_outcome)" do
        let(:body) { { outcome: "loved_it", category_id: phones.id } }

        run_test! { expect(response.parsed_body["code"]).to eq("invalid_outcome") }
      end
    end
  end

  it "is for signed-in sellers only" do
    suggest(as: {})
    expect(response).to have_http_status(:unauthorized)

    report({ outcome: "accepted", category_id: phones.id }, as: {})
    expect(response).to have_http_status(:unauthorized)
  end

  it "logs every answer, suggestion or not (no photo, no user)" do
    suggest
    expect(Rails.logger).to logged(/category_suggestion event=suggested category_id=#{phones.id} confidence=0.62/)

    allow(CategorySuggestion).to receive(:call).and_return(nil)
    suggest
    expect(Rails.logger).to logged(/category_suggestion event=none\z/)
  end

  it "answers 204, not an error, for a blank photo (a covered lens)" do
    allow(ImageSearch::Embedder).to receive(:embed).and_raise(ImageSearch::Embedder::PlainImage, "plain image")

    suggest
    expect(response).to have_http_status(:no_content)
  end

  it "never stores the photo" do
    expect { suggest }.not_to change { [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count ] }
  end

  it "refuses a request without a photo" do
    suggest({})
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("image_missing")
  end

  it "refuses a photo over 10 MB" do
    stub_const("Listing::MAX_IMAGE_SIZE", 10)

    suggest
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("image_too_large")
  end

  it "answers 503 category_suggestion_unavailable when the server cannot suggest" do
    allow(ImageSearch::TextEmbedder).to receive(:available?).and_return(false)

    suggest
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["code"]).to eq("category_suggestion_unavailable")
  end

  it "limits a seller to 30 suggestions per 10 minutes" do
    30.times { suggest }
    expect(response).to have_http_status(:ok)

    suggest
    expect(response).to have_http_status(:too_many_requests)
  end

  it "rounds the reported confidence and refuses an outcome without a category" do
    report({ outcome: "dismissed", category_id: phones.id, confidence: 0.123456 })
    expect(response).to have_http_status(:no_content)
    expect(Rails.logger).to logged(/event=dismissed category_id=#{phones.id} confidence=0.123\z/)

    report({ outcome: "replaced" })
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
