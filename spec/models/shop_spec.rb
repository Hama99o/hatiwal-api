require "rails_helper"

# SHOP-1 — hatiwal-mobile/docs/SHOPS.md
RSpec.describe Shop, type: :model do
  let(:owner) { create(:user) }

  describe "validations" do
    it "is valid with only name, category and location" do
      shop = described_class.new(owner: owner, name: "Safi", category: create(:category),
                                 latitude: 34.35, longitude: 62.2, address_line: "Near the bank")
      expect(shop).to be_valid
    end

    it "requires a 2–50 character name" do
      expect(build(:shop, name: "A")).not_to be_valid
      expect(build(:shop, name: "A" * 51)).not_to be_valid
    end

    it "refuses a location outside Afghanistan, Pakistan and Iran" do
      shop = build(:shop, latitude: 25.2, longitude: 55.27) # Dubai
      expect(shop).not_to be_valid
      expect(shop.errors.details[:base]).to include(error: :outside_service_area)
    end

    it "accepts well-formed opening hours and rejects the rest" do
      expect(build(:shop, hours: { "sat" => [ %w[08:00 12:00], %w[14:00 20:00] ], "fri" => [] })).to be_valid
      [ { "xyz" => [] }, { "sat" => [ %w[08:00 08:00] ] }, { "sat" => [ %w[8 18] ] }, { "sat" => "08-18" }, :unparseable ].each do |bad|
        expect(build(:shop, hours: bad)).not_to be_valid, bad.inspect
      end
    end

    it "allows one shop per user (phase 1)" do
      create(:shop, owner: owner)
      second = build(:shop, owner: owner)
      expect(second).not_to be_valid
      expect(second.errors.details[:base]).to include(error: :one_shop_per_user)
    end

    it "has its messages in all four locales" do
      User::SUPPORTED_LANGUAGES.each do |locale|
        I18n.with_locale(locale) do
          shop = described_class.new
          shop.errors.add(:base, :outside_service_area)
          shop.errors.add(:base, :one_shop_per_user)
          shop.errors.add(:hours, :malformed)
          listing = Listing.new
          listing.errors.add(:shop, :not_a_member)
          messages = shop.errors.full_messages + listing.errors.full_messages
          expect(messages.join).not_to include("Translation missing"), locale
          expect(I18n.t("shops.errors.cannot_sell_as", raise: true)).to be_present
        end
      end
    end
  end

  it "adds the owner as its first member" do
    shop = create(:shop, owner: owner)
    expect(shop.shop_members.map { |m| [ m.user_id, m.role ] }).to eq([ [ owner.id, "owner" ] ])
  end

  it "names its province from the point when none is given" do
    expect(create(:shop, province: nil).province).to eq("Herat")
  end

  describe "SHOP_APPROVAL_REQUIRED" do
    around do |ex|
      old = ENV.fetch("SHOP_APPROVAL_REQUIRED", nil)
      ex.run
    ensure
      old.nil? ? ENV.delete("SHOP_APPROVAL_REQUIRED") : ENV["SHOP_APPROVAL_REQUIRED"] = old
    end

    it "is off by default: a new shop is live at once" do
      ENV.delete("SHOP_APPROVAL_REQUIRED")
      expect(create(:shop)).to be_active
    end

    it "holds new shops for an admin when on" do
      ENV["SHOP_APPROVAL_REQUIRED"] = "true"
      expect(create(:shop)).to be_pending
    end
  end

  it "builds /s/<id> share links from PUBLIC_SHARE_BASE_URL" do
    shop = create(:shop)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.com/")
    expect(described_class.share_url_for(shop)).to eq("https://hatiwal.com/s/#{shop.id}")
  end

  describe "#move_listings!" do
    it "moves only the user's own listings, in and back out" do
      shop = create(:shop, owner: owner)
      mine = create_list(:listing, 2, :active, user: owner)
      other = create(:listing, :active)
      expect(shop.move_listings!(owner, (mine + [ other ]).map(&:id))).to eq(2)
      expect(mine.map { |l| l.reload.shop_id }).to all(eq(shop.id))
      expect(other.reload.shop_id).to be_nil
      expect(shop.move_listings!(owner, [ mine.first.id ], to_shop: false)).to eq(1)
      expect(mine.first.reload.shop_id).to be_nil
    end
  end

  it "counts live products for many shops in one query" do
    a = create(:shop)
    b = create(:shop)
    create_list(:listing, 2, :active, user: a.owner, shop: a)
    create(:listing, :sold, user: a.owner, shop: a)
    create(:listing, :active, user: b.owner, shop: b)
    queries = 0
    counts = ActiveSupport::Notifications.subscribed(->(*) { queries += 1 }, "sql.active_record") do
      described_class.live_listings_counts([ a.id, b.id ])
    end
    expect(counts).to eq(a.id => 2, b.id => 1)
    expect(queries).to eq(1)
  end

  it "gives its products back to the owner when deleted" do
    shop = create(:shop, owner: owner)
    listing = create(:listing, :active, user: owner, shop: shop)
    owner.update!(active_shop: shop)
    shop.destroy!
    expect(listing.reload.shop_id).to be_nil
    expect(owner.reload.active_shop_id).to be_nil
  end

  describe "#close! — the owner closes it, or deletes their account" do
    let(:admin) { create(:admin_user) }
    let(:shop) { create(:shop, :verification_eligible, owner: owner) }

    def verified_with_number!
      request = create(:shop_verification_request, shop: shop, document_number: "KBL-2021/0456")
      request.approve!(admin: admin)
      request
    end

    it "closing (DELETE) takes the shop off public but keeps the row, the decision and the digest" do
      request = verified_with_number!
      digest = request.reload.document_number_digest
      shop.cover.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: "c.jpg", content_type: "image/jpeg")
      staff = create(:shop_member, shop: shop).user
      staff.update!(active_shop: shop)
      product = shop.listings.first

      shop.close!

      expect(shop.reload).to have_attributes(status: "closed", phone: nil, address_line: nil, description: nil,
                                             latitude: nil, longitude: nil, verified_at: nil, name: shop.name)
      expect(shop.logo.attached? || shop.cover.attached?).to be(false)
      expect(shop.shop_members).to be_empty
      expect(staff.reload.active_shop_id).to be_nil
      expect(product.reload).to have_attributes(shop_id: nil, removed_at: nil) # personal again
      expect(described_class.visible).not_to include(shop)
      expect(request.reload).to have_attributes(status: "approved", document_number: nil, name_on_document: nil,
                                                document_number_digest: digest)
      expect(request.files_count).to eq(0)
    end

    it "lets the owner open a new shop after closing one" do
      shop.close!
      expect(build(:shop, owner: owner)).to be_valid
    end

    it "an account deletion closes their shop and removes its products like every listing; the digest survives" do
      request = verified_with_number!
      digest = request.reload.document_number_digest
      product = shop.listings.first
      owner.update!(active_shop: shop)

      owner.anonymize_account!

      expect(shop.reload).to be_closed
      expect(owner.reload.active_shop_id).to be_nil
      expect(product.reload).to have_attributes(shop_id: nil, removed_reason: "account_deleted")
      expect(Listing.browsable).not_to include(product)
      expect(VerificationRequest.where(document_number_digest: digest)).to exist
    end

    it "an account deletion only ends their membership in someone else's shop" do
      other = create(:shop)
      create(:shop_member, shop: other, user: owner)
      owner.anonymize_account!
      expect(other.reload.shop_members.where(user: owner)).to be_empty
      expect(other).to be_active
    end
  end
end
