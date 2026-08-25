require "rails_helper"

# A listing must carry at least one photo before it goes live: this is a
# photo-first marketplace, and a photoless card renders as the grey "no photo"
# box, which reads to buyers as broken or fake. Nothing enforced it before —
# `listingSchema` on mobile never validated `photos`, and the API never looked.
#
# The rule is scoped to the draft -> active transition ONLY, which is what these
# examples pin down: nothing that is already published may become un-editable,
# un-renewable or un-sellable because of a rule added after it was created.
RSpec.describe "Listing#publish" do
  let(:seller) { create(:user) }

  def attach_photo(listing)
    listing.images.attach(
      io:           File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
      filename:     "test_image.jpg",
      content_type: "image/jpeg"
    )
  end

  it "publishes a draft that has a photo and starts the expiry clock in one write" do
    listing = create(:listing, user: seller)
    attach_photo(listing)

    expect(listing.publish).to be(true)
    expect(listing.reload).to be_active
    expect(listing.published_at).to be_present
    expect(listing.expires_at).to be_within(1.minute).of(Listing::LISTING_LIFESPAN.from_now)
  end

  it "refuses to publish a draft with no photo and leaves it a draft" do
    listing = create(:listing, user: seller)

    expect(listing.publish).to be(false)
    expect(listing.errors[:base].join).to match(/at least one photo/)
    expect(listing.reload).to be_draft
  end

  it "keeps a photoless draft saveable — 'Save draft' must not need a photo" do
    listing = build(:listing, user: seller)

    expect(listing.save).to be(true)
  end

  it "leaves an already-active photoless listing editable" do
    listing = create(:listing, :active, user: seller)

    expect(listing.update(title: "Reduced — must go")).to be(true)
  end

  it "leaves an already-active photoless listing sellable" do
    listing = create(:listing, :active, user: seller)

    expect(listing.sold!).to be(true)
  end

  it "does not block reactivating a photoless reserved listing after a deal falls through" do
    listing = create(:listing, :reserved, user: seller)

    expect(listing.active!).to be(true)
  end
end
