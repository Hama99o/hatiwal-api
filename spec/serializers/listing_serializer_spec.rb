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

  describe ":detailed view — seller response rate fields" do
    let(:buyer) { create(:user) }

    subject(:seller_hash) do
      described_class.render_as_hash(listing, view: :detailed, current_user: buyer)[:seller]
    end

    it "includes response_rate_percent key (nil when below threshold)" do
      expect(seller_hash).to have_key(:response_rate_percent)
      expect(seller_hash[:response_rate_percent]).to be_nil
    end

    it "includes response_time_label key (nil when below threshold)" do
      expect(seller_hash).to have_key(:response_time_label)
      expect(seller_hash[:response_time_label]).to be_nil
    end

    context "when seller has >=5 conversations with quick replies" do
      before do
        5.times do
          unique_buyer = create(:user)
          conv = create(:conversation, listing: listing, buyer: unique_buyer, seller: seller)
          first_msg = create(:message, conversation: conv, user: unique_buyer,
                                       created_at: conv.created_at + 1.minute)
          create(:message, conversation: conv, user: seller,
                           created_at: first_msg.created_at + 30.minutes)
        end
        seller.instance_variable_set(:@seller_response_stats, nil)
      end

      it "returns response_rate_percent as a non-nil integer" do
        expect(seller_hash[:response_rate_percent]).to be_an(Integer)
        expect(seller_hash[:response_rate_percent]).to eq(100)
      end

      it "returns response_time_label as a string" do
        expect(seller_hash[:response_time_label]).to eq("within_one_hour")
      end
    end
  end

  describe ":detailed view — seller last_active_label" do
    let(:buyer) { create(:user) }

    subject(:seller_hash) do
      described_class.render_as_hash(listing, view: :detailed, current_user: buyer)[:seller]
    end

    context "when seller signed in within the last 24 hours" do
      before { seller.update_column(:last_sign_in_at, 1.hour.ago) }

      it 'returns "today"' do
        expect(seller_hash[:last_active_label]).to eq("today")
      end
    end

    context "when seller signed in 3 days ago" do
      before { seller.update_column(:last_sign_in_at, 3.days.ago) }

      it 'returns "this_week"' do
        expect(seller_hash[:last_active_label]).to eq("this_week")
      end
    end

    context "when seller signed in 20 days ago" do
      before { seller.update_column(:last_sign_in_at, 20.days.ago) }

      it 'returns "this_month"' do
        expect(seller_hash[:last_active_label]).to eq("this_month")
      end
    end

    context "when seller signed in 60 days ago (beyond 30-day window)" do
      before { seller.update_column(:last_sign_in_at, 60.days.ago) }

      it "returns nil" do
        expect(seller_hash[:last_active_label]).to be_nil
      end
    end

    context "when seller has never signed in (last_sign_in_at is nil)" do
      before { seller.update_column(:last_sign_in_at, nil) }

      it "returns nil" do
        expect(seller_hash[:last_active_label]).to be_nil
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

  describe ":detailed view — share_url field" do
    context "when PUBLIC_SHARE_BASE_URL is set" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.example.com")
      end

      it "returns a full https URL with the listing id" do
        result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
        expect(result[:share_url]).to eq("https://hatiwal.example.com/l/#{listing.id}")
      end

      it "returns a String" do
        result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
        expect(result[:share_url]).to be_a(String)
      end

      it "handles a trailing slash in the base URL gracefully" do
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.example.com/")
        result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
        expect(result[:share_url]).to eq("https://hatiwal.example.com/l/#{listing.id}")
      end
    end

    context "when PUBLIC_SHARE_BASE_URL is not set (nil)" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return(nil)
      end

      it "returns nil" do
        result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
        expect(result[:share_url]).to be_nil
      end
    end

    context "when PUBLIC_SHARE_BASE_URL is an empty string" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("")
      end

      it "returns nil" do
        result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
        expect(result[:share_url]).to be_nil
      end
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

  describe ":detailed view — seller away mode (seller_is_away + seller_away_until)" do
    let(:buyer) { create(:user) }

    subject(:seller_hash) do
      described_class.render_as_hash(listing, view: :detailed, current_user: buyer)[:seller]
    end

    context "when seller is not away (away_until is nil)" do
      before { seller.update_column(:away_until, nil) }

      it "returns seller_is_away as false" do
        expect(seller_hash[:seller_is_away]).to be(false)
      end

      it "returns seller_away_until as nil" do
        expect(seller_hash[:seller_away_until]).to be_nil
      end
    end

    context "when seller's away_until is in the past (auto-expired)" do
      before { seller.update_column(:away_until, 2.days.ago) }

      it "returns seller_is_away as false" do
        expect(seller_hash[:seller_is_away]).to be(false)
      end

      it "returns seller_away_until as nil (stale date never surfaces)" do
        expect(seller_hash[:seller_away_until]).to be_nil
      end
    end

    context "when seller is currently away (away_until is in the future)" do
      before { seller.update_column(:away_until, 5.days.from_now) }

      it "returns seller_is_away as true" do
        expect(seller_hash[:seller_is_away]).to be(true)
      end

      it "returns seller_away_until as an ISO-8601 string" do
        expect(seller_hash[:seller_away_until]).to be_a(String)
        expect { Time.parse(seller_hash[:seller_away_until]) }.not_to raise_error
      end
    end
  end

  describe ":list view — away fields not included in seller block" do
    it "does not include seller_is_away in the list view seller block" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result[:seller]).not_to have_key(:seller_is_away)
    end

    it "does not include seller_away_until in the list view seller block" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result[:seller]).not_to have_key(:seller_away_until)
    end
  end

  # ── negotiable field — present in :list, :detailed, and :seller_list ────────
  describe ":list view — negotiable" do
    it "includes negotiable as true by default" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result).to have_key(:negotiable)
      expect(result[:negotiable]).to be(true)
    end

    it "reflects negotiable: false when set on the listing" do
      listing.update!(negotiable: false)
      result = described_class.render_as_hash(listing, view: :list)
      expect(result[:negotiable]).to be(false)
    end
  end

  describe ":detailed view — negotiable" do
    it "includes negotiable as true by default" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result).to have_key(:negotiable)
      expect(result[:negotiable]).to be(true)
    end

    it "reflects negotiable: false when set on the listing" do
      listing.update!(negotiable: false)
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:negotiable]).to be(false)
    end
  end

  describe ":seller_list view — negotiable" do
    it "includes negotiable as true by default" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).to have_key(:negotiable)
      expect(result[:negotiable]).to be(true)
    end

    it "reflects negotiable: false when set on the listing" do
      listing.update!(negotiable: false)
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result[:negotiable]).to be(false)
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
