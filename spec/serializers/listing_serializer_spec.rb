require "rails_helper"

RSpec.describe ListingSerializer, type: :serializer do
  let(:seller) { create(:user) }
  let(:listing) { create(:listing, :active, user: seller) }

  describe ":detailed view — seller phone gating" do
    subject(:seller_hash) do
      result = described_class.render_as_hash(listing, view: :detailed, **opts)
      result[:seller]
    end

    context "when no current_user (guest)" do
      let(:opts) { { current_user: nil } }

      it "returns nil for phone" do
        expect(seller_hash[:phone]).to be_nil
      end

      it "still returns other seller fields" do
        expect(seller_hash[:id]).to eq(seller.id)
        expect(seller_hash[:name]).to eq(seller.full_name)
        expect(seller_hash[:city]).to eq(seller.city)
        expect(seller_hash).to have_key(:verified)
        expect(seller_hash).to have_key(:avatar_url)
      end
    end

    context "when current_user is the listing owner" do
      let(:opts) { { current_user: seller } }

      it "returns nil for phone (owner viewing their own listing)" do
        expect(seller_hash[:phone]).to be_nil
      end
    end

    context "when current_user is an authenticated non-owner" do
      let(:buyer) { create(:user) }
      let(:opts) { { current_user: buyer } }

      it "returns the seller's phone number" do
        expect(seller_hash[:phone]).to eq(seller.phone)
      end
    end
  end

  describe ":detailed view — analytics fields" do
    it "includes views_count as an integer" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result).to have_key(:views_count)
      expect(result[:views_count]).to be_a(Integer)
    end

    it "includes conversations_count as an integer" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result).to have_key(:conversations_count)
      expect(result[:conversations_count]).to be_a(Integer)
    end

    it "conversations_count reflects actual conversation records" do
      buyer = create(:user)
      create(:conversation, listing: listing, buyer: buyer, seller: seller)
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:conversations_count]).to eq(1)
    end
  end

  describe ":list view" do
    it "does not include a phone field at all" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result[:seller]).not_to have_key(:phone)
    end

    it "includes price_drop_percent as nil when no recent drop" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result).to have_key(:price_drop_percent)
      expect(result[:price_drop_percent]).to be_nil
    end

    it "includes price_dropped_at as nil when no recent drop" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result).to have_key(:price_dropped_at)
      expect(result[:price_dropped_at]).to be_nil
    end

    context "when a recent price drop exists" do
      before { create(:listing_price_history, :recent_drop, listing: listing) }

      it "returns the drop percentage" do
        result = described_class.render_as_hash(listing, view: :list)
        expect(result[:price_drop_percent]).to be_an(Integer)
        expect(result[:price_drop_percent]).to be > 0
      end

      it "returns price_dropped_at as an ISO-8601 string" do
        result = described_class.render_as_hash(listing, view: :list)
        expect(result[:price_dropped_at]).to be_a(String)
      end
    end

    context "when the price drop is older than 14 days" do
      before { create(:listing_price_history, :old_drop, listing: listing) }

      it "returns price_drop_percent as nil" do
        result = described_class.render_as_hash(listing, view: :list)
        expect(result[:price_drop_percent]).to be_nil
      end
    end
  end

  describe ":seller_list view" do
    it "does not include a seller hash (and therefore no phone)" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).not_to have_key(:seller)
    end

    it "includes conversations_count in seller_list view" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).to have_key(:conversations_count)
    end

    it "includes price_drop_percent as nil when no recent drop" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).to have_key(:price_drop_percent)
      expect(result[:price_drop_percent]).to be_nil
    end

    it "includes price_dropped_at as nil when no recent drop" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).to have_key(:price_dropped_at)
      expect(result[:price_dropped_at]).to be_nil
    end

    context "when a recent price drop exists" do
      before { create(:listing_price_history, :recent_drop, listing: listing) }

      it "returns the drop percentage" do
        result = described_class.render_as_hash(listing, view: :seller_list)
        expect(result[:price_drop_percent]).to be_an(Integer)
        expect(result[:price_drop_percent]).to be > 0
      end

      it "returns price_dropped_at as an ISO-8601 string" do
        result = described_class.render_as_hash(listing, view: :seller_list)
        expect(result[:price_dropped_at]).to be_a(String)
      end
    end
  end
end
