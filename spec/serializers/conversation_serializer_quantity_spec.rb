require "rails_helper"

# The chat surfaces must be able to say "14,000 each".
#
# ConversationSerializer hand-rolls its own small listing hash rather than
# reusing ListingSerializer, so a field added to the listing views does NOT
# reach the inbox row or the thread header. That is how a buyer ends up reading
# a per-unit price as the price of all 15 bags in the one place the deal is
# actually struck (docs/SPIKE_LISTING_QUANTITY.md §0c).
RSpec.describe ConversationSerializer, "multi-quantity fields on the nested listing" do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }
  let(:listing) do
    create(:listing, user: seller, status: :active, price: 14_000, quantity: 15, sold_units: 4)
  end
  let(:conversation) { create(:conversation, listing: listing, buyer: buyer) }

  def listing_payload(view)
    JSON.parse(described_class.render(conversation, view: view, current_user: buyer))["listing"]
  end

  %i[list detailed].each do |view|
    context "view :#{view}" do
      subject(:payload) { listing_payload(view) }

      it "sends multi_unit, the flag the clients gate the 'each' suffix on" do
        expect(payload["multi_unit"]).to be(true)
      end

      it "sends what is LEFT, not the seller's original count" do
        expect(payload["available_units"]).to eq(11)
      end

      it "still sends the price the suffix qualifies" do
        # A decimal column serializes as a string — the assertion is that the
        # figure is intact, not that Blueprinter changed its type.
        expect(payload["price"].to_f).to eq(14_000.0)
      end
    end
  end

  context "a single-unit listing — the majority case" do
    let(:listing) { create(:listing, user: seller, status: :active) }

    it "reports multi_unit false on both views, so no chat surface changes at all" do
      expect(listing_payload(:list)["multi_unit"]).to be(false)
      expect(listing_payload(:detailed)["multi_unit"]).to be(false)
    end
  end

  context "a removed listing" do
    it "still sends no listing block at all — the new fields must not resurrect it" do
      # `listing_deleted?` is Conversation#listing.nil? || listing.removed?, so
      # the removed path is the one a live conversation actually takes.
      conversation
      listing.take_down!(reason: "spam")
      expect(listing_payload(:list)).to be_nil
    end
  end
end
