require "rails_helper"

# Multi-quantity fields must appear on EVERY view, not just detail.
#
# Why this spec exists rather than trusting the serializer: the clients gate
# per-unit price rendering ("AFN 14,000 each") on `multi_unit`. A view that
# omitted it would render a bare price for a 15-unit listing and recreate the
# exact "40,000 — each or total?" ambiguity the feature exists to remove
# (docs/SPIKE_LISTING_QUANTITY.md §0c). The feed is the view most likely to be
# forgotten, so it is asserted first.
RSpec.describe ListingSerializer, "multi-quantity fields" do
  let(:seller) { create(:user) }
  let(:listing) { create(:listing, user: seller, status: :active, quantity: 15, sold_units: 4) }

  def render(view)
    JSON.parse(described_class.render(listing, view: view))
  end

  # :owner_detailed inherits :detailed, so all four views a client can receive.
  %i[list seller_list detailed owner_detailed].each do |view|
    context "view :#{view}" do
      subject(:payload) { render(view) }

      it "sends quantity" do
        expect(payload["quantity"]).to eq(15)
      end

      it "sends available_units, so the buyer sees what is left and not the original count" do
        expect(payload["available_units"]).to eq(11)
      end

      it "sends multi_unit, the flag every client gates its quantity UI on" do
        expect(payload["multi_unit"]).to be(true)
      end
    end
  end

  context "a single-unit listing — the majority case" do
    let(:listing) { create(:listing, user: seller, status: :active) }

    it "reports multi_unit false, so no client renders any quantity UI at all" do
      expect(render(:list)["multi_unit"]).to be(false)
      expect(render(:detailed)["multi_unit"]).to be(false)
    end

    it "still reports the counts, so a client never has to guess" do
      expect(render(:list)["quantity"]).to eq(1)
      expect(render(:list)["available_units"]).to eq(1)
    end
  end
end
