require "rails_helper"

# Security review of the 1.2.0 API diff (release-1.1.8..offline-phase2a, 2026-10-28):
# what the offline-mode additions must never give one user about another. The
# cases already covered elsewhere are not repeated (idempotency_spec: keys per
# user; not_managed_spec: a stranger's 404; message_client_uuid_spec: one
# sender's uuid in another chat; identity_isolation_spec: shop_id refusals).
RSpec.describe "Offline-mode security (1.2.0 review)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def json = JSON.parse(response.body)
  def h(user) = auth_headers_for(user).merge("Content-Type" => "application/json")

  let(:category) { create(:category) }

  describe "Idempotency-Key" do
    let(:alice) { create(:user) }
    let(:bob)   { create(:user) }
    let(:key)   { SecureRandom.uuid }
    let(:body)  { { listing: { title: "Bike", price: 3000, currency: "AFN", category_id: category.id } } }

    def create_listing(user)
      post "/api/v1/my/listings", params: body, headers: h(user).merge("Idempotency-Key" => key), as: :json
    end

    it "another user reusing a key with the SAME request never gets the first user's stored answer" do
      create_listing(alice)
      alices = json.dig("listing", "id") || json["id"]

      create_listing(bob)
      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotent-Replayed"]).to be_nil
      bobs = json.dig("listing", "id") || json["id"]
      expect(bobs).not_to eq(alices)
      expect(Listing.find(bobs).user).to eq(bob)
      expect(IdempotencyKey.where(key: key).pluck(:user_id)).to contain_exactly(alice.id, bob.id)
    end

    it "a stored answer is not replayed to its own user once they are banned" do
      create_listing(alice)
      alice.update!(status: :banned)
      expect { create_listing(alice) }.not_to change(Listing, :count)
      # Refused before the replay can run: at sign-in by token (401), or by the ban check (403).
      expect(response.status).to be_in([ 401, 403 ])
      expect(response.headers["Idempotent-Replayed"]).to be_nil
      expect(response.body).not_to include("Bike")
    end

    it "a replay after losing access returns only the original answer: nothing runs again" do
      owner = create(:user)
      shop = create(:shop, owner: owner)
      staff = create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) }
      product = create(:listing, :active, user: owner, shop: shop, title: "Old")
      put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "New" } },
                                                headers: h(staff).merge("Idempotency-Key" => key), as: :json
      expect(response).to have_http_status(:ok)
      shop.remove_team_member!(staff, by: owner)
      product.update_columns(title: "Changed by the owner")

      put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "New" } },
                                                headers: h(staff).merge("Idempotency-Key" => key), as: :json
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(json.dig("listing", "title") || json["title"]).to eq("New") # the snapshot they were sent, not today's row
      expect(product.reload.title).to eq("Changed by the owner")
    end
  end

  describe "403 *_not_managed vs 404" do
    let(:owner) { create(:user) }
    let(:shop)  { create(:shop, owner: owner) }
    let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }

    it "a former member probing a listing the shop made AFTER they left learns nothing: 404" do
      staff
      shop.remove_team_member!(staff, by: owner)
      later = travel_to(1.minute.from_now) { create(:listing, user: owner, shop: shop) } # a draft they never saw

      delete "/api/v1/my/listings/#{later.id}", headers: h(staff)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("listing_not_managed")
    end

    it "a former member of ANOTHER shop learns nothing about this one: 404" do
      outsider = create(:user)
      other_owner = create(:user)
      other_shop = create(:shop, owner: other_owner)
      other_shop.shop_members.create!(user: outsider, role: :staff)
      other_shop.remove_team_member!(outsider, by: other_owner)
      product = create(:listing, :active, user: owner, shop: shop)

      put "/api/v1/my/listings/#{product.id}", params: { listing: { title: "x" } }, headers: h(outsider), as: :json
      expect(response).to have_http_status(:not_found)
      expect(product.reload.title).not_to eq("x")
    end
  end

  describe "edit conflicts (base / 409)" do
    let(:owner) { create(:user) }
    let(:shop)  { create(:shop, owner: owner) }
    let(:staff) { create(:user).tap { |u| shop.shop_members.create!(user: u, role: :staff) } }
    let(:product) { create(:listing, :active, user: owner, shop: shop, price: 250) }

    it "names the teammate who changed the field — to a manager of the listing only" do
      put "/api/v1/my/listings/#{product.id}", params: { listing: { price: 260 } }, headers: h(staff), as: :json
      put "/api/v1/my/listings/#{product.id}", params: { listing: { price: 231, base: { price: 250 } } }, headers: h(owner), as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("fields", "price", "changed_by_name")).to eq(staff.full_name)
    end

    it "a stranger with a base gets a plain 404: no conflict, no name, no value" do
      put "/api/v1/my/listings/#{product.id}", params: { listing: { price: 260 } }, headers: h(staff), as: :json
      put "/api/v1/my/listings/#{product.id}", params: { listing: { price: 1, base: { price: 250 } } }, headers: h(create(:user)), as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("changed_by", staff.full_name.to_s)
    end

    it "who edited what (field_edits, user ids) is never in a listing's public JSON" do
      put "/api/v1/my/listings/#{product.id}", params: { listing: { price: 260 } }, headers: h(staff), as: :json
      get "/api/v1/listings/#{product.id}", headers: h(create(:user))

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("field_edits")
    end
  end

  describe "shop_id on create" do
    let(:seller) { create(:user) }
    let(:body)   { { listing: { title: "Bike", price: 3000, currency: "AFN", category_id: category.id } } }

    it "a shop that does not exist and a stranger's shop answer the same: existence is not revealed" do
      foreign = create(:shop, owner: create(:user))
      post "/api/v1/my/listings", params: body.merge(shop_id: foreign.id), headers: h(seller), as: :json
      foreign_answer = [ response.status, json ]
      post "/api/v1/my/listings", params: body.merge(shop_id: Shop.maximum(:id).to_i + 1000), headers: h(seller), as: :json

      expect([ response.status, json ]).to eq(foreign_answer)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(seller.listings.count).to eq(0)
    end

    it "a suspended user cannot post into their own shop: refused, nothing created" do
      shop = create(:shop, owner: seller)
      headers = h(seller)
      seller.update!(status: :suspended)
      post "/api/v1/my/listings", params: body.merge(shop_id: shop.id), headers: headers, as: :json

      expect(response.status).to be_in([ 401, 403 ])
      expect(Listing.where(shop: shop).count).to eq(0)
    end

    it "a closed or suspended shop is refused, its own owner included" do
      %i[closed suspended].each do |status|
        shop = create(:shop, owner: seller, status: status)
        post "/api/v1/my/listings", params: body.merge(shop_id: shop.id), headers: h(seller), as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json["code"]).to eq("shop_unavailable")
      end
      expect(seller.listings.count).to eq(0)
    end
  end

  describe "listing_rules in the app config" do
    it "carries the public limits only" do
      get "/api/v1/app_config", params: { platform: "android", version: "1.2.0" }

      expect(response).to have_http_status(:ok)
      rules = json.dig("data", "listing_rules") || json["listing_rules"]
      expect(rules.keys).to match_array(%w[title_max description_max price_max quantity_min quantity_max max_photos
                                           photo_required_to_publish video_max_seconds video_max_bytes])
      expect(rules.values).to all(satisfy { |v| v.is_a?(Numeric) || v == true || v == false })
      expect(response.body).not_to match(/prohibited|term|secret|token|key/i)
    end
  end

  describe "image_order" do
    let(:seller)  { create(:user) }
    let(:mine)    { create(:listing, :active, :with_image, user: seller) }
    let(:theirs)  { create(:listing, :active, :with_image, user: create(:user)) }

    it "another listing's photo (its signed id) cannot be referenced: ignored, untouched" do
      foreign_blob = theirs.images.first.blob
      before = foreign_blob.metadata.dup
      put "/api/v1/my/listings/#{mine.id}", params: { listing: { title: "Mine", image_order: [ foreign_blob.signed_id ] } },
                                             headers: h(seller), as: :json

      expect(response).to have_http_status(:ok)
      expect(foreign_blob.reload.metadata).to eq(before)
      expect(mine.reload.images.map(&:blob_id)).not_to include(foreign_blob.id)
    end

    it "a huge token list costs at most MAX_IMAGES blob lookups" do
      own = mine.images.first.blob.signed_id
      allow(ActiveStorage::Blob).to receive(:find_signed).and_call_original
      put "/api/v1/my/listings/#{mine.id}", params: { listing: { title: "Mine", image_order: Array.new(500, own) } },
                                             headers: h(seller), as: :json

      expect(response).to have_http_status(:ok)
      expect(ActiveStorage::Blob).to have_received(:find_signed).at_most(Listing::MAX_IMAGES).times
    end
  end

  describe "client_uuid" do
    it "another participant sending my client_uuid gets their OWN new message, never mine" do
      seller = create(:user)
      buyer = create(:user)
      listing = create(:listing, :active, user: seller)
      conversation = create(:conversation, listing: listing, buyer: buyer, seller: seller)
      uuid = SecureRandom.uuid
      post "/api/v1/conversations/#{conversation.id}/messages", params: { body: "Mine", client_uuid: uuid }, headers: h(seller), as: :json
      mine = json.dig("message", "id") || json["id"]

      post "/api/v1/conversations/#{conversation.id}/messages", params: { body: "Theirs", client_uuid: uuid }, headers: h(buyer), as: :json
      expect(response).to have_http_status(:created)
      theirs = json.dig("message", "id") || json["id"]
      expect(theirs).not_to eq(mine)
      expect(Message.find(theirs).user).to eq(buyer)
      expect(Message.find(mine).body).to eq("Mine")
    end
  end

  describe "Retry-After" do
    def reset(email, ip)
      post "/api/v1/auth/password", params: { email: email }, headers: { "REMOTE_ADDR" => ip }, as: :json
    end

    it "is the same for an address with an account and one without: it does not tell them apart" do
      user = create(:user)
      answers = [ user.email, "nobody-#{SecureRandom.hex(4)}@example.com" ].map.with_index do |email, n|
        4.times { |i| reset(email, "10.9.#{n}.#{i + 1}") }
        [ response.status, response.headers["Retry-After"], response.body ]
      end

      expect(answers.first.first).to eq(429)
      expect(answers.first).to eq(answers.last)
    end
  end
end
