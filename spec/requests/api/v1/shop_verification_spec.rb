require "swagger_helper"

# SHOP-1 × VER-1 — a shop applies for "Verified shop" through the same
# verification requests as a person (hatiwal-mobile/docs/SHOPS.md, "Verified shops").
RSpec.describe "Shop verification", type: :request do
  let(:shop)    { create(:shop, :verification_eligible) }
  let(:owner)   { shop.owner }
  let(:headers) { auth_headers_for(owner) }
  let(:image)   { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg") }
  let(:apply_params) do
    { subject: "shop:#{shop.id}",
      verification_request: { document_type: "e_tazkira", document_number: "1234564821", phone: "+93 70 123 4567",
                              front: image, back: image, proof: image } }
  end

  path "/api/v1/verification_requests" do
    post "apply for Verified shop (subject=shop:<id>)" do
      tags "Shops"
      description "A shop owner or manager applies: front = the shop front with its sign, back = the business " \
                  "the owner's e-Tazkira (back) + its number, a proof of business (proof), phone = a number the team calls back. No selfie."
      consumes "multipart/form-data"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :subject, in: :formData, type: :string, example: "shop:12"
      parameter name: :verification_request, in: :formData, schema: {
        type: :object,
        properties: {
          document_type: { type: :string, enum: VerificationRequest::SHOP_DOCUMENT_TYPES },
          phone: { type: :string },
          front: { type: :string, format: :binary, description: "the shop front, sign visible" },
          back: { type: :string, format: :binary, description: "the owner's e-Tazkira" },
          proof: { type: :string, format: :binary, description: "proof of business: licence, rental contract, tax paper…" },
          document_number: { type: :string, description: "the owner's e-Tazkira number" }
        },
        required: %w[document_type document_number phone front back proof]
      }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "201", "sent; the status card is the shop's" do
        let(:subject) { "shop:#{shop.id}" }
        let(:verification_request) { apply_params[:verification_request] }

        run_test! do
          expect(shop.verification_requests.requested.count).to eq(1)
          expect(JSON.parse(response.body)["verification_status"]["status"]).to eq("requested")
        end
      end
    end
  end

  def apply(as: headers, params: apply_params)
    post "/api/v1/verification_requests", params: params, headers: as
  end

  it "refuses someone who does not manage the shop" do
    apply(as: auth_headers_for(create(:user)))
    expect(response).to have_http_status(:forbidden)
  end

  it "says what is missing for a shop without a logo or products" do
    bare = create(:shop, owner: create(:user))
    apply(as: auth_headers_for(bare.owner), params: apply_params.merge(subject: "shop:#{bare.id}"))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("logo").and include("live_product")
  end

  it "needs the phone and both photos" do
    apply(params: apply_params.merge(verification_request: { document_type: "passport" }))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "reads the shop's status card" do
    get "/api/v1/verification_requests/current", params: { subject: "shop:#{shop.id}" }, headers: headers
    expect(JSON.parse(response.body)["verification_status"]).to include("status" => "none", "missing" => [])
  end

  it "rejects an unknown subject" do
    get "/api/v1/verification_requests/current", params: { subject: "shop:0" }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "never puts a document in the response" do
    apply
    expect(response.body).not_to match(/front|back|blob|rails\/active_storage/i)
  end
end

RSpec.describe VerificationRequest, "for a shop", type: :model do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:request) { create(:shop_verification_request) }
  let(:shop) { request.subject }

  it "approving verifies the shop (not the owner) and tells the owner" do
    expect { request.approve!(admin: admin, checklist: { "shop_real" => "1" }) }
      .to have_enqueued_job(SupportNoticeJob).with(shop.owner_id, "shop_verified")
    expect(shop.reload).to have_attributes(verified_by_id: admin.id)
    expect(shop.verified?).to be(true)
    expect(shop.owner.reload.verified).to be(false)
    expect(request.reload.checklist).to include("shop_real" => true, "phone_works" => false)
  end

  it "rejecting and revoking tell the owner too" do
    expect { request.reject!(admin: admin, reason_code: "shop_sign_not_visible") }
      .to have_enqueued_job(SupportNoticeJob).with(shop.owner_id, "shop_verification_rejected")
    again = create(:shop_verification_request, shop: shop)
    again.approve!(admin: admin)
    expect { again.revoke!(admin: admin, reason_code: "policy_violation") }
      .to have_enqueued_job(SupportNoticeJob).with(shop.owner_id, "shop_badge_removed")
    expect(shop.reload.verified?).to be(false)
  end

  it "a name/address change drops the badge but never rewrites the decided request" do
    request.approve!(admin: admin)
    decided_at = request.reload.decided_at
    shop.reload.update!(name: "Another name")
    expect(shop.drop_badge_after_identity_change!).to be(true)
    expect(shop.reload.verified?).to be(false)
    expect(request.reload).to have_attributes(status: "approved", decided_at: decided_at, decided_by_id: admin.id)
    expect(VerificationStatus.new(shop.reload)).to have_attributes(state: "none", name_changed?: true)
  end

  it "keeps the badge for changes that are not the name or address" do
    request.approve!(admin: admin)
    shop.reload.update!(description: "New description", hours: { "sat" => [ %w[09:00 17:00] ] })
    expect(shop.drop_badge_after_identity_change!).to be(false)
    expect(shop.reload.verified?).to be(true)
  end

  it "sends the shop notices in the owner's language, all four locales" do
    request.approve!(admin: admin)
    User::SUPPORTED_LANGUAGES.each do |locale|
      %w[shop_verified shop_verification_rejected shop_badge_removed shop_reverify_needed].each do |key|
        text = I18n.t("support.notices.#{key}", locale: locale, shop: "Safi", reason: "x", name: "A", raise: true)
        expect(text).to include("Safi")
      end
    end
  end
end

RSpec.describe "Admin — shop verification queue", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let!(:request_record) { create(:shop_verification_request) }

  before { sign_in admin, scope: :admin_user }

  it "lists shop requests under Shops and opens the shop card" do
    get admin_verification_requests_path(kind: "shops")
    expect(response.body).to include(request_record.subject.name)
    get admin_verification_requests_path(kind: "users")
    expect(response.body).not_to include(request_record.subject.name)

    get admin_verification_request_path(request_record)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("verify-shop-facts", "Shop front", "Pin is at the shop")
  end

  it "approves a shop from the card" do
    patch approve_admin_verification_request_path(request_record), params: { checklist: { shop_real: "1" } }
    expect(request_record.subject.reload.verified?).to be(true)
  end
end

RSpec.describe VerificationRequest, "shop document numbers", type: :model do
  it "keeps the owner's e-Tazkira number normalized, so it matches the same ID on a person's request" do
    shop_request = create(:shop_verification_request, document_number: "۱۲۳۴-۵۶۷۸۹")
    expect(shop_request.document_number).to eq("123456789")
    expect(shop_request.document_number_digest).to eq(described_class.digest_for("123456789"))
  end

  it "requires the owner's e-Tazkira number and a proof of business (owner, 2026-10-05)" do
    shop = create(:shop, :verification_eligible)
    expect(build(:shop_verification_request, shop: shop, document_number: nil)).not_to be_valid
    no_proof = build(:shop_verification_request, shop: shop)
    no_proof.proof.detach
    expect(no_proof).not_to be_valid
    expect(build(:shop_verification_request, shop: shop, document_type: :licence)).not_to be_valid
  end
end

RSpec.describe "Shop edit after verification", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:verification) { create(:shop_verification_request) }
  let(:shop) { verification.subject }
  let(:headers) { auth_headers_for(shop.owner).merge("Content-Type" => "application/json") }

  before { verification.approve!(admin: admin) }

  it "the owner renaming the shop drops the badge and tells them, in their language" do
    expect do
      patch "/api/v1/shops/#{shop.id}", params: { shop: { name: "Renamed" } }.to_json, headers: headers
    end.to have_enqueued_job(SupportNoticeJob).with(shop.owner_id, "shop_reverify_needed")
    expect(shop.reload.verified?).to be(false)
    get "/api/v1/verification_requests/current", params: { subject: "shop:#{shop.id}" }, headers: headers
    expect(JSON.parse(response.body)["verification_status"]).to include("status" => "none", "name_changed" => true)
  end
end
