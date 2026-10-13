require "rails_helper"

# Prohibited items: the Support message a seller receives when a listing is
# taken down or auto-drafted, in en / ps / fa (anything else reads English).
RSpec.describe SupportNoticeJob, "prohibited-item notices", type: :job do
  include ActiveJob::TestHelper

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return("true")
  end

  def body_for(user)
    Conversation.kind_support.find_by(buyer_id: user.id, shop_id: nil).messages.sole.body
  end

  def run(listing, key = "listing_prohibited_removed", data = {})
    described_class.perform_now(listing.user_id, key, listing.shop_id, { "listing_id" => listing.id }.merge(data))
  end

  {
    "en" => [ "taken off Hatiwal", "firearms, hunting guns included", "https://hatiwal.com/en/prohibited-items" ],
    "ps" => [ "هټیوال", "د ښکار ټوپکو", "https://hatiwal.com/ps/prohibited-items" ],
    "fa" => [ "هتیوال", "تفنگ شکاری", "https://hatiwal.com/fa/prohibited-items" ]
  }.each do |locale, expected|
    it "tells the seller in #{locale}: what, why (the category) and the link" do
      seller = create(:user, firstname: "Gul", preferred_language: locale)
      listing = create(:listing, :active, user: seller, title: "Rifle")

      run(listing, "listing_prohibited_removed", "category" => "firearms")

      expect(body_for(seller)).to include("Gul", "«Rifle»", *expected)
      expect(body_for(seller)).to eq(I18n.t("support.notices.listing_prohibited_removed", locale: locale, name: "Gul", title: "Rifle",
                                                                                          reason: I18n.t("support.prohibited.reasons.firearms", locale: locale),
                                                                                          warning: "", note: "", link: "https://hatiwal.com/#{locale}/prohibited-items"))
    end
  end

  it "writes Urdu, or any other language, in English" do
    seller = create(:user, preferred_language: "ur")
    run(create(:listing, :active, user: seller), "listing_prohibited_removed", "category" => "drugs")
    expect(body_for(seller)).to include("drugs and narcotics are not allowed on Hatiwal", "/en/prohibited-items")
  end

  it "has a reason in every locale for every category" do
    ProhibitedTerm::CATEGORIES.each_key do |category|
      %i[en ps fa].each do |locale|
        expect(I18n.t("support.prohibited.reasons.#{category}", locale: locale, raise: true)).to be_present
      end
    end
  end

  it "adds the admin's note and the warning count" do
    seller = create(:user, preferred_language: "ps")
    run(create(:listing, :active, user: seller), "listing_prohibited_removed", "category" => "alcohol", "note" => "دا شراب دی", "warnings" => 2)
    expect(body_for(seller)).to include("دا شراب دی", "(2 له 3 څخه)")
  end

  it "files an unknown category under other" do
    seller = create(:user, preferred_language: "en")
    run(create(:listing, :active, user: seller), "listing_prohibited_removed", "category" => "bogus")
    expect(body_for(seller)).to include(I18n.t("support.prohibited.reasons.other", locale: :en))
  end

  it "explains the automatic move to drafts" do
    seller = create(:user, preferred_language: "fa")
    run(create(:listing, user: seller, title: "X"), "listing_prohibited_auto_drafted")
    expect(body_for(seller)).to include("چند نفر", "https://hatiwal.com/fa/prohibited-items")
  end

  it "speaks in the shop's thread for a shop's listing" do
    owner = create(:user, preferred_language: "en")
    shop = create(:shop, owner: owner)
    listing = create(:listing, :active, user: owner, shop: shop)
    run(listing, "listing_prohibited_removed", "category" => "adult")
    expect(Conversation.kind_support.find_by(shop_id: shop.id).messages.sole.body).to include("adult content")
  end

  it "says nothing for a deleted listing" do
    seller = create(:user)
    described_class.perform_now(seller.id, "listing_prohibited_removed", nil, { "listing_id" => 0 })
    expect(Conversation.kind_support.where(buyer_id: seller.id)).to be_empty
  end

  it "refuses an unknown key on enqueue" do
    expect { described_class.enqueue_prohibited(create(:listing), :nope) }.to raise_error(ArgumentError)
  end
end
