require "rails_helper"

# SF-B11 — an offer carries how many units it is for.
#
# The gap, end to end: mobile's `firstMessageQuantity.ts` writes a buyer's
# quantity into the opening message as PROSE ("3 × AFN 14,000 = AFN 42,000") and
# says in its own header that "the quantity is never persisted as structured data
# anywhere"; `OfferSheet.tsx` says "an offer carries no quantity of its own, so
# nothing downstream disambiguates it"; and `Listing#units_for_sale` therefore
# defaults a batch sale to ONE unit. A seller who agreed to sell 3 had to
# remember and re-type 3 — and when they didn't, `sold_units` moved by 1, stock
# read 14 where it should have read 12, and the listing started advertising units
# it no longer had. That is docs/SPIKE_LISTING_QUANTITY.md's own top risk ("a
# stale number lies to buyers") reached from a different direction, and the spike
# named this exact fix before deferring it (§13.4).
RSpec.describe Message, "offer quantity (SF-B11)", type: :model do
  let(:seller) { create(:user) }
  let(:buyer)  { create(:user) }

  # 15 units, none sold — `available_units` 15.
  let(:batch)        { create(:listing, :active, user: seller, quantity: 15) }
  let(:batch_thread) { create(:conversation, listing: batch, buyer: buyer) }

  # The single-item listing every existing listing in the app is. Nothing about
  # it may change, on any path.
  let(:single)        { create(:listing, :active, user: seller, quantity: 1) }
  let(:single_thread) { create(:conversation, listing: single, buyer: buyer) }

  def offer(thread, quantity: nil, kind: :offer, user: buyer)
    build(:message, :offer, conversation: thread, user: user, kind: kind, offer_quantity: quantity)
  end

  describe "storing a stated quantity" do
    it "keeps it on an offer on a multi-unit listing" do
      message = offer(batch_thread, quantity: 3)

      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to eq(3)
    end

    it "keeps it on an offer_counter too — a counter has to be able to restate how many" do
      original = create(:message, :offer, conversation: batch_thread, user: buyer)
      counter  = build(:message, :offer_counter, conversation: batch_thread, user: seller,
                                                 responds_to: original, offer_quantity: 4)

      expect(counter).to be_valid
      counter.save!
      expect(counter.reload.offer_quantity).to eq(4)
    end

    it "accepts exactly `available_units` (the boundary is inclusive)" do
      expect(offer(batch_thread, quantity: 15)).to be_valid
    end

    it "measures the ceiling against what is LEFT, not the listing's total" do
      batch.update!(sold_units: 12) # 3 left of 15

      expect(offer(batch_thread, quantity: 3)).to be_valid
      expect(offer(batch_thread, quantity: 4)).not_to be_valid
    end
  end

  # The regression guard for every offer that already exists. `nil` means "the
  # sender said nothing", which is a DIFFERENT fact from "one" — and the column
  # is deliberately not defaulted to 1 so the two stay distinguishable forever.
  describe "an offer with NO quantity" do
    it "is valid on a multi-unit listing and stores nil, not 1" do
      message = offer(batch_thread, quantity: nil)

      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end

    it "is valid on a single-item listing and stores nil" do
      message = offer(single_thread, quantity: nil)

      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end

    it "leaves a plain text message untouched" do
      message = create(:message, conversation: batch_thread, user: buyer, body: "Is this still available?")

      expect(message.reload.offer_quantity).to be_nil
    end
  end

  # "Only meaningful on a multi-unit listing" — the governing rule. Discarded
  # rather than refused, exactly as `Listing#units_for_sale` and
  # `#reserve_with_buyer!` already ignore the param for one unit, so a stale or
  # over-eager client can never invent a new 422 on a flow that works today.
  describe "a single-item listing" do
    it "discards a quantity instead of storing it" do
      message = offer(single_thread, quantity: 3)

      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end

    it "discards a quantity that would be over-available rather than 422-ing" do
      message = offer(single_thread, quantity: 99)

      expect(message).to be_valid
      expect(message.error_code).to be_nil
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end

    it "discards it on a SOLD-OUT single item too — nothing about one unit can fail here" do
      single.update!(sold_units: 1, status: :sold)

      message = offer(single_thread, quantity: 1)
      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end
  end

  describe "a kind that is not an offer" do
    %i[text meetup_proposal offer_accepted offer_declined document image_message].each do |kind|
      it "discards a quantity sent with kind #{kind}" do
        message = build(:message, conversation: batch_thread, user: buyer, kind: kind,
                                  body: "whatever", offer_quantity: 5)

        expect(message).to be_valid
        message.save!
        expect(message.reload.offer_quantity).to be_nil
      end
    end
  end

  describe "a conversation whose listing is gone" do
    # `Listing has_many :conversations, dependent: :nullify` — an orphaned thread
    # legitimately has listing_id nil, and there is then no `available_units` to
    # measure against.
    it "discards the quantity rather than raising" do
      batch_thread.update_column(:listing_id, nil)

      message = offer(batch_thread.reload, quantity: 3)
      expect(message).to be_valid
      message.save!
      expect(message.reload.offer_quantity).to be_nil
    end
  end

  describe "more units than the listing has left" do
    it "is refused, not clamped" do
      message = offer(batch_thread, quantity: 20)

      expect(message).not_to be_valid
      expect(message.errors[:offer_quantity]).not_to be_empty
      # The whole point of refusing: the number is NOT quietly rewritten to 15.
      expect(message.offer_quantity).to eq(20)
      expect { message.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "carries the machine-readable code, so a ps/fa client never shows the English string" do
      message = offer(batch_thread, quantity: 20)
      message.valid?

      expect(message.error_code).to eq(Message::OFFER_QUANTITY_ABOVE_AVAILABLE_CODE)
      expect(message.error_code).to eq("offer_quantity_above_available_units")
    end

    it "names the real ceiling in the message" do
      batch.update!(sold_units: 3) # 12 left

      message = offer(batch_thread, quantity: 13)
      message.valid?

      expect(message.errors.full_messages.join).to eq(
        "Offer quantity cannot be more than the 12 units still available. Set it to 12 or fewer."
      )
    end

    it "singularizes at one unit left" do
      batch.update!(sold_units: 14) # 1 left

      message = offer(batch_thread, quantity: 2)
      message.valid?

      expect(message.errors.full_messages.join).to include("the 1 unit still available")
    end

    # A sold-out batch's thread stays open — a listing is still message-able
    # after it sells, only the stock is gone — so "0 units still available. Set
    # it to 0 or fewer." was reachable prose. It gets its own sentence.
    it "says something sane when there is nothing left at all" do
      batch.update!(sold_units: 15)

      message = offer(batch_thread, quantity: 1)
      message.valid?

      expect(message.errors.full_messages.join).to eq(
        "Offer quantity cannot be set — this listing has no units left."
      )
      expect(message.error_code).to eq(Message::OFFER_QUANTITY_ABOVE_AVAILABLE_CODE)
    end
  end

  describe "a non-positive quantity" do
    [ 0, -1 ].each do |bad|
      it "refuses #{bad}" do
        message = offer(batch_thread, quantity: bad)

        expect(message).not_to be_valid
        expect(message.errors[:offer_quantity]).not_to be_empty
      end
    end

    # It is a client bug, not a state the sender can act on, so it gets NO code —
    # only the available-units ceiling does.
    it "carries no wire code" do
      message = offer(batch_thread, quantity: 0)
      message.valid?

      expect(message.error_code).to be_nil
    end

    it "refuses a fractional quantity" do
      message = offer(batch_thread, quantity: "2.5")

      expect(message).not_to be_valid
      expect(message.errors[:offer_quantity]).not_to be_empty
    end
  end

  describe "#error_code" do
    it "is nil for every other validation failure — those 422s are unchanged" do
      blank_body = build(:message, conversation: batch_thread, user: buyer, body: "")
      blank_body.valid?
      expect(blank_body.error_code).to be_nil

      cross_thread = build(:message, conversation: batch_thread, user: buyer,
                                     kind: :meetup_accepted, body: "ok",
                                     responds_to_id: create(:message).id)
      cross_thread.valid?
      expect(cross_thread.error_code).to be_nil
    end

    it "is nil on a valid record" do
      expect(offer(batch_thread, quantity: 3).tap(&:valid?).error_code).to be_nil
    end
  end

  describe "#offer_kind?" do
    it "is true for offer and offer_counter only" do
      expect(build(:message, kind: :offer).offer_kind?).to be(true)
      expect(build(:message, kind: :offer_counter).offer_kind?).to be(true)

      %i[text meetup_proposal meetup_accepted meetup_declined offer_accepted
         offer_declined document image_message].each do |kind|
        expect(build(:message, kind: kind).offer_kind?).to be(false)
      end
    end
  end

  # The backstop for everything that bypasses validation — update_column, raw
  # SQL, Administrate — written for the same reason as
  # `listings_quantity_positive`.
  describe "the DB check constraint" do
    it "rejects a non-positive quantity written past the model" do
      message = create(:message, :offer, conversation: batch_thread, user: buyer, offer_quantity: 3)

      expect { message.update_column(:offer_quantity, 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /messages_offer_quantity_positive/)
    end

    it "still allows NULL — 'unspecified' has to stay legal" do
      message = create(:message, :offer, conversation: batch_thread, user: buyer, offer_quantity: 3)

      expect { message.update_column(:offer_quantity, nil) }.not_to raise_error
      expect(message.reload.offer_quantity).to be_nil
    end
  end
end
