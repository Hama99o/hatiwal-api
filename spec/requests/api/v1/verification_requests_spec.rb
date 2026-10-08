require "swagger_helper"

# VER-1: apply for the Verified badge. Documents must NEVER come back in a
# response — not to the owner, not after sending (docs/VERIFICATION.md).
RSpec.describe "Api::V1::VerificationRequests", type: :request do
  let(:user)    { create(:user, :verification_eligible) }
  let(:headers) { auth_headers_for(user) }
  let(:image)   { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }

  # Nothing that could fetch a file: no URL, no blob key, no signed id.
  def expect_no_documents(body)
    raw = body.is_a?(String) ? body : body.to_json
    expect(raw).not_to match(%r{https?://|/rails/active_storage|blob|signed_id|"key"}i)
    VerificationRequest.find_each do |r|
      r.attached_files.each { |name| expect(raw).not_to include(r.public_send(name).blob.key) }
    end
  end

  path "/api/v1/verification_requests/current" do
    get "the verification status card for the caller" do
      tags "Verification"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :subject, in: :query, type: :string, required: false, description: "me (default). shop:<id> comes with SHOP-1."
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:subject)        { "me" }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }
        run_test!
      end

      response "200", "none, with nothing missing" do
        run_test! do |response|
          status = response.parsed_body["verification_status"]
          expect(status).to include("status" => "none", "missing" => [], "request" => nil)
        end
      end

      response "200", "under review, without any document" do
        before { create(:verification_request, :two_sided, user: user) }

        run_test! do |response|
          status = response.parsed_body["verification_status"]
          expect(status["status"]).to eq("requested")
          expect(status["request"]).to include("document_type" => "e_tazkira", "document_last4" => "4821", "files_count" => 3,
                                               "files_purged" => false)
          expect_no_documents(response.body)
        end
      end

      response "200", "rejected, its photos deleted after the keep period (request.files_purged)" do
        before do
          request = create(:verification_request, :two_sided, user: user)
          request.reject!(admin: create(:admin_user), reason_code: "photo_not_clear")
          request.update_columns(decided_at: (VerificationRequest::FILES_KEPT_FOR + 1.day).ago)
          request.purge_files!
        end

        run_test! do |response|
          status = response.parsed_body["verification_status"]
          expect(status["status"]).to eq("rejected")
          expect(status["request"]).to include("files_purged" => true, "files_count" => 0, "reason_code" => "photo_not_clear")
        end
      end
    end
  end

  path "/api/v1/verification_requests" do
    post "apply for the Verified badge (multipart)" do
      tags "Verification"
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      description "3 requests sent per day. Answers the status card; never a document."
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :verification_request, in: :formData, schema: {
        type: :object,
        properties: {
          document_type: { type: :string, enum: VerificationRequest::USER_DOCUMENT_TYPES },
          name_on_document: { type: :string },
          document_number: { type: :string, pattern: "^\\d{6,20}$", description: "the FULL number; kept encrypted, never returned" },
          front: { type: :string, format: :binary },
          back: { type: :string, format: :binary, description: "the back of the e-Tazkira" },
          selfie: { type: :string, format: :binary, description: "holding the document" }
        },
        required: %w[document_type name_on_document document_number front back selfie]
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:verification_request) do
        { document_type: "e_tazkira", name_on_document: user.full_name, document_number: "1234564821", front: image, back: image, selfie: image }
      end

      response "201", "sent; the card says under review, with no document" do
        run_test! do |response|
          expect(response.parsed_body.dig("verification_status", "status")).to eq("requested")
          expect_no_documents(response.body)
        end
      end

      response "422", "a two-sided document needs its back" do
        let(:verification_request) do
          { document_type: "e_tazkira", name_on_document: user.full_name, document_number: "1234564821", front: image, selfie: image }
        end
        run_test!
      end
    end
  end

  path "/api/v1/verification_requests/{id}" do
    delete "cancel a waiting request (its photos are deleted at once)" do
      tags "Verification"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :id, in: :path, type: :integer, required: true
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:id)             { create(:verification_request, user: user).id }

      response "200", "cancelled; the card is back to none" do
        run_test! do |response|
          expect(response.parsed_body.dig("verification_status", "status")).to eq("none")
        end
      end

      response "404", "someone else's request" do
        let(:id) { create(:verification_request).id }
        run_test!
      end
    end
  end

  describe "POST /api/v1/verification_requests" do
    def apply(as: user, **attrs)
      params = { document_type: "e_tazkira", name_on_document: "Umair Safi", document_number: "1234564821", front: image, back: image, selfie: image }
      post "/api/v1/verification_requests", params: { verification_request: params.merge(attrs) }, headers: auth_headers_for(as)
    end

    it "sends the request; the card says under review, with no document in it" do
      apply
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig("verification_status", "status")).to eq("requested")
      expect(response.parsed_body.dig("verification_status", "request", "files_count")).to eq(3) # front, back, selfie
      expect_no_documents(response.body)
      expect(user.verification_requests.sole).to have_attributes(requested_by: user, document_last4: "4821")
    end

    it "needs the back of the e-Tazkira" do
      apply(back: nil)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Owner, 2026-10-05: only the e-Tazkira is accepted.
    it "refuses a paper Tazkira, CNIC, Kart-e Melli and passport" do
      %w[tazkira cnic kart_melli passport].each do |type|
        apply(document_type: type)
        expect(response).to have_http_status(:unprocessable_entity), type
      end
      expect(VerificationRequest.count).to eq(0)
    end

    it "keeps the full number encrypted, shows only the last 4, and never returns it" do
      apply(document_number: "۱۲۳ ۴۵۶-۴۸۲۱") # Persian digits, spaces and a dash
      expect(response).to have_http_status(:created)
      request = user.verification_requests.sole
      expect(request.document_number).to eq("1234564821")
      expect(request.document_last4).to eq("4821")
      expect(response.body).not_to include("1234564821")
      expect(response.body).not_to include(request.document_number_digest)
      raw = VerificationRequest.connection.select_value("SELECT document_number FROM verification_requests WHERE id = #{request.id}")
      expect(raw).not_to include("1234564821") # ciphertext in the database
    end

    it "rejects a number that is too short or too long" do
      apply(document_number: "1234")
      expect(response).to have_http_status(:unprocessable_entity)
      apply(document_number: "1" * 21)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(VerificationRequest.count).to eq(0)
    end

    it "never logs the number" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      expect(filter.filter("verification_request" => { "document_number" => "1234564821" }).to_s).not_to include("1234564821")
    end

    it "does not tell the applicant when the same number is on another account" do
      create(:verification_request) # same factory number, another account
      apply
      expect(response).to have_http_status(:created)
      expect(response.body).not_to match(/already|duplicate|same/i)
    end

    it "rejects an unknown document type with a 422, not a 500" do
      apply(document_type: "driving_licence")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a licence (shops only)" do
      apply(document_type: "licence")
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires the selfie" do
      apply(selfie: nil)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows only one open request at a time" do
      create(:verification_request, user: user)
      apply
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.verification_requests.requested.count).to eq(1)
    end

    it "refuses a user who is not eligible yet" do
      newcomer = create(:user, :confirmed)
      apply(as: newcomer)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses an already verified user" do
      user.update!(verified: true)
      apply
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "is limited to 3 requests SENT a day; failed uploads do not count" do
      4.times { apply(selfie: nil) } # four blurry/incomplete tries: all 422, none counted
      expect(response).to have_http_status(:unprocessable_entity)

      3.times do
        apply
        expect(response).to have_http_status(:created)
        user.verification_requests.requested.sole.cancel!
      end
      apply
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to include("code" => "verification_daily_limit")
    end

    it "explains the daily limit in the person's language" do
      user.update!(preferred_language: "ps")
      3.times { create(:verification_request, user: user).cancel! }
      apply
      expect(response.parsed_body["message"]).to eq(I18n.t("verification.errors.daily_limit", locale: :ps))
    end

    it "lets a rejected user apply again at once" do
      create(:verification_request, user: user).reject!(admin: create(:admin_user), reason_code: "photo_not_clear")
      apply
      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /api/v1/verification_requests/current" do
    it "lists what is missing for someone who cannot apply yet" do
      newcomer = create(:user)
      get "/api/v1/verification_requests/current", headers: auth_headers_for(newcomer)
      expect(response.parsed_body.dig("verification_status", "missing")).to eq(%w[email_confirmed avatar])
    end

    it "shows the reason of a rejection in the person's language" do
      user.update!(preferred_language: "fa")
      create(:verification_request, user: user).reject!(admin: create(:admin_user), reason_code: "photo_not_clear")
      get "/api/v1/verification_requests/current", headers: headers
      status = response.parsed_body["verification_status"]
      expect(status).to include("status" => "rejected", "reason" => I18n.t("verification.reasons.photo_not_clear", locale: :fa))
      expect(status.dig("request", "reason_code")).to eq("photo_not_clear")
    end

    it "shows verified since the approval" do
      create(:verification_request, user: user).approve!(admin: create(:admin_user))
      get "/api/v1/verification_requests/current", headers: headers
      expect(response.parsed_body.dig("verification_status", "status")).to eq("verified")
      expect(response.parsed_body.dig("verification_status", "verified_since")).to be_present
    end

    it "refuses an unknown subject, in the person's language" do
      user.update!(preferred_language: "fa")
      get "/api/v1/verification_requests/current", params: { subject: "shop:1" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("verification.errors.unknown_subject", locale: :fa))
    end
  end

  describe "DELETE /api/v1/verification_requests/:id" do
    it "cancels a waiting request and deletes its files at once" do
      request = create(:verification_request, user: user)
      delete "/api/v1/verification_requests/#{request.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("verification_status", "status")).to eq("none")
      expect(request.reload).to be_cancelled
      expect(request.files_count).to eq(0)
    end

    it "cannot cancel someone else's request" do
      other = create(:verification_request)
      delete "/api/v1/verification_requests/#{other.id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(other.reload).to be_requested
    end

    it "cannot cancel a decided request" do
      request = create(:verification_request, user: user)
      request.reject!(admin: create(:admin_user), reason_code: "photo_not_clear")
      delete "/api/v1/verification_requests/#{request.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the public Active Storage routes" do
    it "refuse a verification document even with its signed id" do
      request = create(:verification_request, user: user)
      get rails_blob_path(request.front, disposition: "inline")
      expect(response).to have_http_status(:not_found)
    end

    it "still serve an avatar" do
      get rails_blob_path(user.avatar, disposition: "inline")
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "changing the name on a verified account" do
    # Owner decision, 2026-10-08: once verified, a person stays verified.
    it "keeps the badge and the decision; nothing to verify again" do
      request = create(:verification_request, user: user)
      request.approve!(admin: create(:admin_user))
      put "/api/v1/users/me", params: { user: { firstname: "Other", lastname: "Different" } }, headers: headers
      expect(user.reload).to be_verified
      expect(user.full_name).to eq("Other Different")
      expect(request.reload).to be_approved

      get "/api/v1/verification_requests/current", headers: headers
      expect(response.parsed_body["verification_status"]).to include("status" => "verified", "name_changed" => false)
    end

    it "changes nothing for someone who never applied" do
      put "/api/v1/users/me", params: { user: { lastname: "Different" } }, headers: headers
      expect(response).to have_http_status(:ok)
      get "/api/v1/verification_requests/current", headers: headers
      expect(response.parsed_body["verification_status"]).to include("status" => "none", "name_changed" => false)
    end
  end
end
