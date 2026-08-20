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

  describe ":detailed view — seller rating summary" do
    let(:buyer) { create(:user) }

    subject(:seller_hash) do
      described_class.render_as_hash(listing, view: :detailed, current_user: buyer)[:seller]
    end

    it "includes avg_rating and review_count keys" do
      expect(seller_hash).to have_key(:avg_rating)
      expect(seller_hash).to have_key(:review_count)
    end

    it "returns nil avg_rating for a seller with no revealed reviews" do
      expect(seller_hash[:avg_rating]).to be_nil
    end

    context "when the seller has revealed reviews" do
      # Set the denormalized aggregates directly, the way recompute_review_stats!
      # writes them — the serializer contract is what's under test here.
      before { seller.update_columns(review_count: 3, avg_rating: 4.67) }

      it "surfaces the average as a float and the count" do
        expect(seller_hash[:avg_rating]).to eq(4.67)
        expect(seller_hash[:review_count]).to eq(3)
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

  describe ":detailed view — saves_count (saved-by-N social proof)" do
    it "includes saves_count as an integer, guest-visible (nil current_user)" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result).to have_key(:saves_count)
      expect(result[:saves_count]).to be_a(Integer)
    end

    it "is 0 when nobody has saved the listing" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:saves_count]).to eq(0)
    end

    it "matches the exact number of SavedListing records for the listing" do
      create_list(:saved_listing, 3, listing: listing)
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:saves_count]).to eq(3)
      expect(result[:saves_count]).to eq(SavedListing.where(listing: listing).count)
    end

    it "does not expose any saver identity — only the integer total" do
      create(:saved_listing, listing: listing)
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:saves_count]).to be_a(Integer)
      expect(result.keys).not_to include(:savers, :saved_by, :saved_by_users)
    end
  end

  # TASK-K729 dedup fix — the category block now comes from CategorySerializer
  # (shared with ConversationSerializer's listing.category) instead of 3
  # hand-rolled hashes.
  describe "category — shared CategorySerializer shape" do
    it ":list view includes the full CategorySerializer shape" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result[:category][:id]).to eq(listing.category_id)
      expect(result[:category][:name_en]).to eq(listing.category.name_en)
      expect(result[:category][:slug]).to eq(listing.category.slug)
      expect(result[:category]).to have_key(:icon)
      expect(result[:category]).to have_key(:position)
    end

    it ":seller_list view includes the full CategorySerializer shape" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result[:category][:id]).to eq(listing.category_id)
      expect(result[:category][:name_en]).to eq(listing.category.name_en)
      expect(result[:category]).to have_key(:slug)
    end

    it ":detailed view includes the full CategorySerializer shape" do
      result = described_class.render_as_hash(listing, view: :detailed, current_user: nil)
      expect(result[:category][:id]).to eq(listing.category_id)
      expect(result[:category][:slug]).to eq(listing.category.slug)
    end
  end

  describe ":list view — saves_count is not exposed" do
    it "does not include saves_count in the list view" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result).not_to have_key(:saves_count)
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

  # TASK-BE-SAVEDLIST (FlowApp #255) — :list never rendered is_saved at all
  # before this; it only existed on :detailed. Mirrors the existing is_viewed
  # (`viewed_ids`) contract exactly, plus the saved-screen shortcut.
  describe ":list view — is_saved (TASK-BE-SAVEDLIST)" do
    it "is false when no saved_ids/saved_by_listing_id option is passed" do
      result = described_class.render_as_hash(listing, view: :list)
      expect(result).to have_key(:is_saved)
      expect(result[:is_saved]).to be(false)
    end

    it "is true when the listing id is present in the saved_ids Set" do
      result = described_class.render_as_hash(listing, view: :list, saved_ids: Set[listing.id])
      expect(result[:is_saved]).to be(true)
    end

    it "is false when saved_ids is present but does not include the listing id" do
      other_id = listing.id + 1
      result = described_class.render_as_hash(listing, view: :list, saved_ids: Set[other_id])
      expect(result[:is_saved]).to be(false)
    end

    it "is true when the listing id is a key in saved_by_listing_id (My::SavedListings shortcut)" do
      result = described_class.render_as_hash(
        listing, view: :list, saved_by_listing_id: { listing.id => create(:saved_listing, listing: listing) }
      )
      expect(result[:is_saved]).to be(true)
    end

    it "does not raise or default to true for an unrelated row when saved_by_listing_id is present" do
      other_listing = create(:listing, :active)
      result = described_class.render_as_hash(
        other_listing, view: :list, saved_by_listing_id: { listing.id => create(:saved_listing, listing: listing) }
      )
      expect(result[:is_saved]).to be(false)
    end
  end

  # TASK-BE-SAVEDLIST — is_saved must NOT exist on :seller_list. The seller's
  # own My Shop feed has no use for "did I save my own listing".
  describe ":seller_list view — is_saved is not exposed" do
    it "does not include is_saved" do
      result = described_class.render_as_hash(listing, view: :seller_list)
      expect(result).not_to have_key(:is_saved)
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

  # ── TASK-R418 — owner-only `sale` field (buyer identity + agreed price) ────
  describe ":owner_detailed view" do
    it "includes everything :detailed has (include_view)" do
      result = described_class.render_as_hash(listing, view: :owner_detailed)
      detailed_keys = described_class.render_as_hash(listing, view: :detailed).keys
      expect(result.keys).to include(*detailed_keys)
    end

    it "returns sale: nil for a draft/active listing" do
      result = described_class.render_as_hash(listing, view: :owner_detailed)
      expect(result).to have_key(:sale)
      expect(result[:sale]).to be_nil
    end

    context "when reserved with a Transaction" do
      let(:listing) { create(:listing, :reserved, user: seller) }
      let!(:buyer)  { create(:user) }
      let!(:convo)  { create(:conversation, listing: listing, seller: seller, buyer: buyer) }
      let!(:txn) do
        create(:transaction, listing: listing, seller: seller, buyer: buyer, final_price: 5_000)
      end

      it "includes the buyer identity, final price, and conversation_id" do
        result = described_class.render_as_hash(listing, view: :owner_detailed)
        sale = result[:sale]

        expect(sale[:status]).to eq("reserved")
        expect(sale[:final_price].to_f).to eq(5_000.0)
        expect(sale[:buyer][:id]).to eq(buyer.id)
        expect(sale[:buyer][:name]).to eq(buyer.full_name)
        expect(sale[:conversation_id]).to eq(convo.id)
      end

      it "resolves conversation_id from the in-memory array when conversations is preloaded (no extra query)" do
        loaded = Listing.includes(:conversations).find(listing.id)
        result = described_class.render_as_hash(loaded, view: :owner_detailed)
        expect(result[:sale][:conversation_id]).to eq(convo.id)
      end
    end

    it "returns sale: nil for a legacy reserve with no Transaction" do
      legacy = create(:listing, :reserved, user: seller)
      result = described_class.render_as_hash(legacy, view: :owner_detailed)
      expect(result[:sale]).to be_nil
    end
  end

  # ── TASK-R418 — PRIVACY: `sale` must never leak onto the public views ──────
  describe "privacy — :sale is owner-scoped only" do
    let(:reserved_listing) { create(:listing, :reserved, user: seller) }
    let(:buyer)            { create(:user) }

    before do
      create(:conversation, listing: reserved_listing, seller: seller, buyer: buyer)
      create(:transaction, listing: reserved_listing, seller: seller, buyer: buyer)
    end

    it ":detailed never includes a sale key, even for a reserved listing with a real Transaction" do
      result = described_class.render_as_hash(reserved_listing, view: :detailed, current_user: seller)
      expect(result).not_to have_key(:sale)
    end

    it ":list never includes a sale key" do
      result = described_class.render_as_hash(reserved_listing, view: :list)
      expect(result).not_to have_key(:sale)
    end
  end
end
