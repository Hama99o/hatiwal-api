require "swagger_helper"

# SHOP-2 (hatiwal-mobile/docs/SHOPS.md, "Phase 2 — definition of done"):
# several shops per owner but never the same one twice, and "Message shop"
# from the shop page — a chat with the shop that has no product.
RSpec.describe "Shops phase 2", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:category) { create(:category) }
  let(:herat) { { latitude: 34.3529, longitude: 62.204 } }

  def json(headers) = headers.merge("Content-Type" => "application/json")

  describe "the same shop twice (Shop#not_a_duplicate_of_own_shop)" do
    let!(:first) { create(:shop, owner: owner, name: "Safi Store", city: "Herat", address_line: "Chowk-e Golha, 2nd floor", **herat) }

    it "refuses the same normalized name within 200 m, whatever the case, spaces, marks or letter variants" do
      [ "Safi Store", "  safi   STORE!", "Safi-Store" ].each do |name|
        expect(build(:shop, owner: owner, name: name, latitude: 34.3533, longitude: 62.204)).not_to be_valid, name
      end
      persian = create(:shop, owner: owner, name: "صافی", latitude: 34.30, longitude: 62.10)
      dup = build(:shop, owner: owner, name: "صافي", latitude: persian.latitude, longitude: persian.longitude)
      expect(dup).not_to be_valid
      expect(dup.duplicate_shop).to eq(persian)
    end

    it "allows the same name far away (a second branch)" do
      expect(build(:shop, owner: owner, name: "Safi Store", latitude: 34.40, longitude: 62.204)).to be_valid
    end

    it "refuses the same address in the same city, allows it in another city" do
      same = build(:shop, owner: owner, name: "Another", city: "herat", address_line: "chowk-e golha 2nd floor",
                          latitude: 34.36, longitude: 62.21)
      expect(same).not_to be_valid
      other_city = build(:shop, owner: owner, name: "Another", city: "Kabul", address_line: "Chowk-e Golha, 2nd floor",
                                latitude: 34.53, longitude: 69.17)
      expect(other_city).to be_valid
    end

    it "without a city, the same address counts as the same within 5 km" do
      first.update_column(:city, nil)
      expect(build(:shop, owner: owner, name: "Another", city: nil, address_line: "Chowk-e Golha, 2nd floor",
                          latitude: 34.36, longitude: 62.21)).not_to be_valid
      expect(build(:shop, owner: owner, name: "Another", city: nil, address_line: "Chowk-e Golha, 2nd floor",
                          latitude: 34.53, longitude: 69.17)).to be_valid
    end

    it "a closed shop never blocks, and another user's identical shop is fine" do
      expect(build(:shop, owner: create(:user), name: "Safi Store", city: "Herat",
                          address_line: "Chowk-e Golha, 2nd floor", **herat)).to be_valid
      first.close!
      expect(build(:shop, owner: owner, name: "Safi Store", **herat)).to be_valid
    end

    it "an edit onto another of your shops is refused too, with the code and the shop" do
      second = create(:shop, owner: owner, name: "Second", latitude: 34.40, longitude: 62.30)
      patch "/api/v1/shops/#{second.id}", params: { shop: { name: "safi store", **herat } }.to_json,
                                          headers: json(auth_headers_for(owner))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("code" => "shop_duplicate", "duplicate_shop_id" => first.id)
      expect(second.reload.name).to eq("Second")
    end

    it "serializes one owner's shop writes with an advisory lock" do
      allow(Shop).to receive(:lock_owner!).and_call_original
      post "/api/v1/shops", params: { shop: { name: "Third", category_id: category.id, address_line: "Elsewhere", latitude: 34.5,
                                              longitude: 62.5 } }.to_json, headers: json(auth_headers_for(owner))
      expect(response).to have_http_status(:created)
      expect(Shop).to have_received(:lock_owner!).with(owner.id)
    end
  end

  describe "/users/me with several shops" do
    it "lists owned shops first, then the oldest; unread per shop includes a listing-less chat" do
      other_owner_shop = create(:shop)
      other_owner_shop.shop_members.create!(user: owner, role: :staff)
      a = create(:shop, owner: owner, name: "A shop", latitude: 34.30, longitude: 62.1)
      b = create(:shop, owner: owner, name: "B shop", latitude: 34.40, longitude: 62.3)
      buyer = create(:user)
      chat = Conversations::StartShopService.new(buyer: buyer, shop: b, message_body: "Salaam").call
      expect(chat).to be_shop_chat

      get "/api/v1/users/me", headers: auth_headers_for(owner)
      me = JSON.parse(response.body)["user"]
      expect(me["shops"].pluck("id")).to eq([ a.id, b.id, other_owner_shop.id ])
      expect(me["unread_counts"]).to include("selling_me" => 0, "shops" => { b.id.to_s => 1 })
    end
  end

  path "/api/v1/shops/{shop_id}/conversations" do
    post "Message shop (a chat without a product)" do
      tags "Shops"
      description "Find-or-create the caller's one chat with the shop that has no product. 201 when created, 200 with " \
                  "the same chat after. `message` is optional. Refused: own shop / a shop you're a member of " \
                  "(422 code own_shop), a shop that isn't open (404), a blocked pair (422)."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :shop_id, in: :path, type: :integer
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :body, in: :body, schema: { type: :object, properties: { message: { type: :string } } }

      let(:shop) { create(:shop, owner: owner) }
      let(:buyer) { create(:user) }
      let(:headers) { auth_headers_for(buyer) }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:shop_id) { shop.id }
      let(:body) { { message: "Do you have this in blue?" } }

      response "201", "created; listing null, shop set" do
        run_test! do
          c = JSON.parse(response.body)["conversation"]
          expect(c["listing"]).to be_nil
          expect(c["shop"]).to include("id" => shop.id, "name" => shop.name)
        end
      end

      response "422", "your own shop" do
        let(:headers) { auth_headers_for(owner) }

        run_test! { expect(JSON.parse(response.body)["code"]).to eq("own_shop") }
      end

      response "404", "a shop that isn't open" do
        let(:shop) { create(:shop, :suspended, owner: owner) }

        run_test!
      end
    end
  end

  describe "Message shop" do
    let(:shop) { create(:shop, owner: owner) }
    let(:buyer) { create(:user) }

    def message_shop(as: buyer, message: nil)
      post "/api/v1/shops/#{shop.id}/conversations", params: { message: message }.compact.to_json, headers: json(auth_headers_for(as))
    end

    it "is find-or-create: the second tap opens the SAME chat (200), and its message is added and pushed" do
      message_shop
      expect(response).to have_http_status(:created)
      id = JSON.parse(response.body)["conversation"]["id"]
      expect(Conversation.find(id).messages).to be_empty

      expect { message_shop(message: "Salaam") }.to have_enqueued_job(SendMessagePushJob)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["conversation"]["id"]).to eq(id)
      expect(Conversation.where(shop: shop, buyer: buyer).count).to eq(1)
      expect(Conversation.find(id).messages.last.body).to eq("Salaam")
    end

    it "refuses a blocked pair either way" do
      create(:block, blocker: owner, blocked: buyer)
      message_shop(message: "hi")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Conversation.where(shop: shop).count).to eq(0)
    end

    it "the owner sees it under the shop's Chat tab, never under Me; the push carries the shop" do
      message_shop(message: "Salaam")
      id = JSON.parse(response.body)["conversation"]["id"]
      get "/api/v1/conversations", params: { shop_id: shop.id }, headers: auth_headers_for(owner)
      expect(JSON.parse(response.body)["conversations"].pluck("id")).to include(id)
      get "/api/v1/conversations", params: { shop_id: "none" }, headers: auth_headers_for(owner)
      expect(JSON.parse(response.body)["conversations"].pluck("id")).not_to include(id)

      allow(Notifications::ExpoPushService).to receive(:deliver).and_return(Struct.new(:error).new(nil))
      owner.update!(push_token: "ExponentPushToken[x]")
      SendMessagePushJob.perform_now(Conversation.find(id).messages.last.id)
      expect(Notifications::ExpoPushService).to have_received(:deliver).with(hash_including(data: hash_including(shopId: shop.id)))
    end

    it "takes plain messages only: no offers without a product" do
      message_shop
      id = JSON.parse(response.body)["conversation"]["id"]
      post "/api/v1/conversations/#{id}/messages", params: { message: { kind: "offer", body: "500" } }.to_json,
                                                   headers: json(auth_headers_for(buyer))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "a suspended shop: the chat stays readable, new messages are refused with shop_unavailable" do
      message_shop(message: "Salaam")
      id = JSON.parse(response.body)["conversation"]["id"]
      shop.suspended!
      get "/api/v1/conversations/#{id}/messages", headers: auth_headers_for(buyer)
      expect(response).to have_http_status(:ok)
      post "/api/v1/conversations/#{id}/messages", params: { message: { kind: "text", body: "Still there?" } }.to_json,
                                                   headers: json(auth_headers_for(buyer))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("shop_unavailable")
    end
  end

  describe "Support notices name THE shop (an owner with several)" do
    let(:admin) { create(:admin_user) }

    before { allow(Conversation).to receive(:admin_initiate_enabled?).and_return(true) }

    it "approving the second shop congratulates for the second shop, not the first" do
      create(:shop, owner: owner, name: "First Shop", latitude: 34.30, longitude: 62.1)
      second = create(:shop, :verification_eligible, owner: owner, name: "Second Shop", latitude: 34.40, longitude: 62.3)
      request_record = create(:shop_verification_request, shop: second)
      perform_enqueued_jobs(only: SupportNoticeJob) { request_record.approve!(admin: admin) }
      body = Conversation.kind_support.find_by(buyer_id: owner.id).messages.last.body
      expect(body).to include("Second Shop")
      expect(body).not_to include("First Shop")
    end

    it "a job queued before SHOP-2 (no shop id) still sends, about the first shop" do
      shop = create(:shop, :verification_eligible, owner: owner)
      create(:shop_verification_request, shop: shop).approve!(admin: admin)
      clear_enqueued_jobs
      SupportNoticeJob.perform_now(owner.id, "shop_verified")
      expect(Conversation.kind_support.find_by(buyer_id: owner.id).messages.last.body).to include(shop.name)
    end
  end

  it "the first message of a listing chat is pushed and broadcast like every other" do
    listing = create(:listing, :active)
    expect do
      post "/api/v1/listings/#{listing.id}/conversations", params: { message: "Is it still available?" }.to_json,
                                                           headers: json(auth_headers_for(create(:user)))
    end.to have_enqueued_job(SendMessagePushJob).and have_enqueued_job(BroadcastMessageJob)
    expect(response).to have_http_status(:created)
  end
end
