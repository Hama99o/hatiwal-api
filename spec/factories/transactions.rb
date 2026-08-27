FactoryBot.define do
  factory :transaction do
    # `seller` drives `listing` (not the other way around) so that overriding
    # just `seller:` on the factory still produces a listing owned by that
    # seller — required by the `seller_matches_listing_owner` validation.
    # Everything uses explicit `create` (not `association`) so records are
    # always persisted with real ids regardless of the parent's build
    # strategy — validations and the after(:build) hook below both need real
    # foreign keys to compare, even under `FactoryBot.build(:transaction)`.
    seller  { create(:user) }
    listing { create(:listing, :active, user: seller) }
    buyer   { create(:user) }

    final_price { listing.price }
    currency    { listing.currency }
    status      { :reserved }

    # The buyer must be a conversation participant on the listing (model
    # validation) — auto-create one unless the caller already set one up.
    # SF-B3: skipped entirely when there is no buyer (the :outside_buyer trait) —
    # a buyer-less sale has no thread to belong to, and Conversation requires one.
    after(:build) do |txn|
      next if txn.buyer_id.blank?

      unless txn.buyer_id == txn.seller_id || Conversation.exists?(listing_id: txn.listing_id, seller_id: txn.seller_id, buyer_id: txn.buyer_id)
        create(:conversation, listing: txn.listing, seller: txn.seller, buyer: txn.buyer)
      end
    end

    trait :sold do
      status       { :sold }
      completed_at { Time.current }
    end

    # SF-B3 — "sold to someone not on Hatiwal": a real sale, a real ledger row,
    # no counterparty account. `buyer_id` is nullable as of
    # db/migrate/20260827000000_allow_null_buyer_on_transactions.rb.
    trait :outside_buyer do
      status       { :sold }
      completed_at { Time.current }
      buyer        { nil }
    end
  end
end
