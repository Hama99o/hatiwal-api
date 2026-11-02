require "rails_helper"

# Hunt-2 (1.1.7): Active Storage accepts a blob's signed_id string anywhere it
# accepts a file, and listing detail echoes the signed ids of its photos (so the
# edit form can remove one). Anyone could therefore attach SOMEONE ELSE's photo
# blob to their own listing, avatar, shop, chat message or verification
# request, and purging their copy then deleted the owner's file.
# Every upload param on the API is a file uploaded in this request (no client
# sends a signed id there); anything else is refused with 422 invalid_upload and
# nothing is attached.
RSpec.describe "Upload params take only files uploaded in this request", type: :request do
  let(:victim)   { create(:user) }
  let(:attacker) { create(:user, :confirmed) }
  let(:headers)  { auth_headers_for(attacker) }
  let!(:victim_listing) { create(:listing, :active, :with_image, user: victim) }
  let(:victim_blob) { victim_listing.images.first.blob }
  let(:stolen) { victim_blob.signed_id }

  def expect_refused
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["code"]).to eq("invalid_upload")
    expect(ActiveStorage::Attachment.where(blob_id: victim_blob.id).count).to eq(1)
  end

  it "a new listing" do
    post "/api/v1/my/listings", params: { listing: { title: "Mine", price: 10, category_id: create(:category).id, images: [ stolen ] } },
                                headers: headers
    expect_refused
  end

  it "adding photos to my listing" do
    mine = create(:listing, :active, user: attacker)
    patch "/api/v1/my/listings/#{mine.id}", params: { listing: { images: [ stolen ] } }, headers: headers
    expect_refused
  end

  it "my avatar" do
    patch "/api/v1/users/me", params: { user: { avatar: stolen } }, headers: headers
    expect_refused
  end

  it "my shop's logo and cover" do
    shop = create(:shop, owner: attacker)
    patch "/api/v1/shops/#{shop.id}", params: { shop: { logo: stolen } }, headers: headers
    expect_refused
    patch "/api/v1/shops/#{shop.id}", params: { shop: { cover: stolen } }, headers: headers
    expect_refused
  end

  it "a chat attachment" do
    conversation = create(:conversation, buyer: attacker, listing: create(:listing, :active))
    post "/api/v1/conversations/#{conversation.id}/messages", params: { body: "look", attachment: stolen }, headers: headers
    expect_refused
  end

  it "a verification request" do
    post "/api/v1/verification_requests", params: { verification_request: { document_type: "national_id", front: stolen } },
                                          headers: headers
    expect_refused
  end

  it "a real multipart upload still works" do
    mine = create(:listing, :active, user: attacker)
    file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg")
    patch "/api/v1/my/listings/#{mine.id}", params: { listing: { images: [ file ] } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(mine.reload.images.count).to eq(1)
  end
end
