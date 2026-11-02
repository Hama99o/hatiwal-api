require "rails_helper"

# OFFLINE phase 2a (§10.2): the same field check on the profile (another device
# changed it) and on a sale's correction (a teammate changed it).
RSpec.describe "Edits with a base — profile and sale", type: :request do
  let(:seller)  { create(:user, firstname: "Ahmad", bio: "Old bio", city: "Kabul") }
  let(:headers) { auth_headers_for(seller) }

  def body = JSON.parse(response.body)

  describe "PATCH /users/me" do
    def update_me(attrs, base: nil)
      patch "/api/v1/users/me", params: { user: attrs.merge(base ? { base: base } : {}) }, headers: headers, as: :json
    end

    it "nothing changed meanwhile: applied" do
      update_me({ bio: "New bio" }, base: { bio: "Old bio" })
      expect(response).to have_http_status(:ok)
      expect(seller.reload.bio).to eq("New bio")
    end

    it "changed on another device: 409 for that field, the others apply" do
      seller.update!(bio: "Bio from the web")
      update_me({ bio: "New bio", city: "Herat" }, base: { bio: "Old bio", city: "Kabul" })
      expect(response).to have_http_status(:conflict)
      expect(body["code"]).to eq("edit_conflict")
      expect(body["fields"]["bio"]).to include("yours" => "New bio", "theirs" => "Bio from the web")
      expect(seller.reload.bio).to eq("Bio from the web")
      expect(seller.city).to eq("Herat")
      expect(body["user"]["city"]).to eq("Herat")
    end

    it "without a base (1.1.x): overwrites, as before" do
      seller.update!(bio: "Bio from the web")
      update_me({ bio: "New bio" })
      expect(response).to have_http_status(:ok)
      expect(seller.reload.bio).to eq("New bio")
    end
  end

  describe "PATCH /my/transactions/:id (final_price)" do
    let(:buyer) { create(:user) }
    let(:listing) { create(:listing, :active, user: seller, price: 1000) }
    let(:sale) do
      create(:conversation, listing: listing, seller: seller, buyer: buyer)
      put "/api/v1/my/listings/#{listing.id}/sold", params: { buyer_id: buyer.id, final_price: 900 }, headers: headers, as: :json
      listing.sale_transactions.sold.last
    end

    def correct(attrs, base: nil)
      patch "/api/v1/my/transactions/#{sale.id}", params: attrs.merge(base ? { base: base } : {}), headers: headers, as: :json
    end

    it "the price someone else already corrected: 409, theirs kept" do
      sale.update!(final_price: 950)
      correct({ final_price: 850 }, base: { final_price: 900 })
      expect(response).to have_http_status(:conflict)
      expect(body["fields"]["final_price"]).to include("theirs" => 950.0)
      expect(sale.reload.final_price).to eq(950)
    end

    it "nothing changed meanwhile: corrected" do
      correct({ final_price: 850 }, base: { final_price: 900 })
      expect(response).to have_http_status(:ok)
      expect(sale.reload.final_price).to eq(850)
    end
  end
end
