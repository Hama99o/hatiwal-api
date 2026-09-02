require "rails_helper"

# Owner request, 2026-09-02: "add input in backend also… to add whatsapp number
# also and show option to show number and address to people or not — I mean user
# address not list address, its important".
#
# Two things are asserted here that are easy to get wrong:
#   1. the DEFAULTS must preserve today's behaviour, or the change silently
#      withdraws a working feature from every existing seller
#   2. `show_address_publicly` governs the USER's own city/province, never the
#      listing's location, which is a separate field
RSpec.describe "contact visibility", type: :request do
  let(:seller) do
    create(:user, phone: "+93700000001", whatsapp_number: "+93700000002",
                  city: "Kabul", province: "kabul")
  end
  let(:buyer) { create(:user) }
  let(:listing) { create(:listing, :active, user: seller) }

  describe "defaults" do
    it "publishes phone and address, exactly as before this feature existed" do
      expect(seller.show_phone_publicly).to be true
      expect(seller.show_address_publicly).to be true
    end
  end

  describe "the seller hash on a listing" do
    subject(:seller_hash) do
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer)
      JSON.parse(response.body).dig("listing", "seller")
    end

    it "gives an authenticated non-owner the phone AND the whatsapp number" do
      expect(seller_hash["phone"]).to eq("+93700000001")
      expect(seller_hash["whatsapp_number"]).to eq("+93700000002")
    end

    it "withholds both once the seller turns the phone off" do
      seller.update!(show_phone_publicly: false)
      expect(seller_hash["phone"]).to be_nil
      # WhatsApp rides the same switch — hiding one while publishing the other
      # would hide nothing, since both reach the same handset.
      expect(seller_hash["whatsapp_number"]).to be_nil
    end

    it "withholds the seller's own city once they turn the address off" do
      seller.update!(show_address_publicly: false)
      expect(seller_hash["city"]).to be_nil
    end

    it "leaves the LISTING's own location untouched by the address setting" do
      seller.update!(show_address_publicly: false)
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(buyer)
      body = JSON.parse(response.body)["listing"]
      # The listing's location is the item's, not the person's — a seller hiding
      # their home address must not blank out where the item can be collected.
      expect(body["location"]).to eq(listing.location)
    end

    it "returns nil whatsapp when the seller never set one" do
      seller.update!(whatsapp_number: nil)
      expect(seller_hash["whatsapp_number"]).to be_nil
    end

    it "treats an empty whatsapp string as absent, not as an empty link" do
      seller.update!(whatsapp_number: "")
      expect(seller_hash["whatsapp_number"]).to be_nil
    end

    it "still withholds contact details from the owner's own view" do
      get "/api/v1/listings/#{listing.id}", headers: auth_headers_for(seller)
      own = JSON.parse(response.body).dig("listing", "seller")
      expect(own["phone"]).to be_nil
      expect(own["whatsapp_number"]).to be_nil
    end
  end

  describe "the public profile" do
    it "hides the user's province and city when the address is off" do
      seller.update!(show_address_publicly: false)
      get "/api/v1/users/#{seller.id}", headers: auth_headers_for(buyer)
      body = JSON.parse(response.body)["user"]
      expect(body["province"]).to be_nil
      expect(body["city"]).to be_nil
    end

    it "shows them when it is on" do
      get "/api/v1/users/#{seller.id}", headers: auth_headers_for(buyer)
      body = JSON.parse(response.body)["user"]
      expect(body["province"]).to eq("kabul")
    end

    it "never exposes the whatsapp number on a PUBLIC profile" do
      # The public view is a trust dossier, not a contact card. Reaching a seller
      # goes through their listing, which is where the gating lives.
      get "/api/v1/users/#{seller.id}", headers: auth_headers_for(buyer)
      expect(JSON.parse(response.body)["user"]).not_to have_key("whatsapp_number")
    end
  end

  describe "updating my own settings" do
    it "accepts the whatsapp number and both switches" do
      patch "/api/v1/users/me",
            params: { user: { whatsapp_number: "0700123456",
                              show_phone_publicly: false,
                              show_address_publicly: false } },
            headers: auth_headers_for(seller)
      expect(response).to have_http_status(:ok)
      seller.reload
      expect(seller.whatsapp_number).to eq("0700123456")
      expect(seller.show_phone_publicly).to be false
      expect(seller.show_address_publicly).to be false
    end

    it "returns my own settings in the :me view so a client can render them" do
      get "/api/v1/users/me", headers: auth_headers_for(seller)
      body = JSON.parse(response.body)["user"]
      expect(body["whatsapp_number"]).to eq("+93700000002")
      expect(body["show_phone_publicly"]).to be true
      expect(body["show_address_publicly"]).to be true
    end

    it "rejects an absurdly long number rather than storing it" do
      patch "/api/v1/users/me",
            params: { user: { whatsapp_number: "0" * 31 } },
            headers: auth_headers_for(seller)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts any SPELLING of a real number — the clients normalise" do
      # +93…, 0093…, 070… and 70… are all in use; a format regex here would
      # reject numbers people actually have.
      [ "+93 70 012 3456", "0093700123456", "070-012-3456", "700123456" ].each do |n|
        patch "/api/v1/users/me", params: { user: { whatsapp_number: n } },
                                  headers: auth_headers_for(seller)
        expect(response).to have_http_status(:ok), "rejected #{n.inspect}"
      end
    end
  end
end
