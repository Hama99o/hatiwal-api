namespace :db do
  namespace :seed do
    desc "Seed E2E test data — creates known test accounts and listings for Maestro flows"
    task e2e: :environment do
      load Rails.root.join("db/seeds/e2e.rb")
    end

    desc "Reset E2E test data — wipes all e2e accounts and re-seeds from scratch"
    task reset_e2e: :environment do
      E2E_EMAILS = %w[
        buyer@hatiwal.test
        seller@hatiwal.test
        newbuyer@hatiwal.test
      ].freeze

      puts "=== Wiping E2E test data ==="

      users = User.where(email: E2E_EMAILS)

      # Destroy in order to respect foreign keys
      user_ids = users.pluck(:id)

      Report.where(reporter_id: user_ids).delete_all
      SavedListing.where(user_id: user_ids).delete_all

      Message.joins(:conversation)
             .where(conversations: { buyer_id: user_ids })
             .or(Message.joins(:conversation).where(conversations: { seller_id: user_ids }))
             .delete_all

      Conversation.where(buyer_id: user_ids).or(Conversation.where(seller_id: user_ids)).delete_all

      listing_ids = Listing.where(user_id: user_ids).pluck(:id)

      # Every table with an FK into `listings` or `transactions` has to go first,
      # or Postgres refuses the delete below. This list is the FULL set as of the
      # multi-quantity work — confirmed against the live FK graph, not guessed:
      #
      #   saved_listings · conversations · listing_views · listing_price_histories
      #   hidden_listings · transactions   -> listings
      #   reviews                          -> transactions
      #
      # It used to cover only the first two plus price histories, so the reset
      # broke PERMANENTLY the first time a QA run sold, viewed or hid an e2e
      # listing — `PG::ForeignKeyViolation ... "fk_rails_68f018eb40" on table
      # "transactions"`, with the wipe half-done and the seed never reached.
      # Selling is now a routine QA step (docs/SPIKE_LISTING_QUANTITY.md), so
      # this was guaranteed to bite on every run.
      #
      # Matched on the e2e USER ids as well as the listing ids: a transaction can
      # hang off an e2e buyer while the listing belongs to someone else, and
      # deleting the user would then violate the same constraint from the other
      # side.
      txn_ids = Transaction.where(listing_id: listing_ids)
                           .or(Transaction.where(seller_id: user_ids))
                           .or(Transaction.where(buyer_id: user_ids))
                           .pluck(:id)
      Review.where(transaction_id: txn_ids)
            .or(Review.where(reviewer_id: user_ids))
            .or(Review.where(reviewee_id: user_ids))
            .delete_all
      Transaction.where(id: txn_ids).delete_all

      ListingView.where(listing_id: listing_ids).or(ListingView.where(user_id: user_ids)).delete_all
      HiddenListing.where(listing_id: listing_ids).or(HiddenListing.where(user_id: user_ids)).delete_all
      ListingPriceHistory.where(listing_id: listing_ids).delete_all
      # LISTING-scoped saves, not just the e2e users' own.
      #
      # Line ~24 already clears `SavedListing.where(user_id: user_ids)` — every
      # save MADE BY an e2e persona. It cannot catch a save made BY SOMEONE ELSE
      # POINTING AT an e2e listing, and that is enough to abort the whole wipe:
      #
      #   PG::ForeignKeyViolation: update or delete on table "listings" violates
      #   foreign key constraint "fk_rails_63efe8ab53" on table "saved_listings"
      #
      # Which is exactly the failure the `saved_searches` note below already
      # describes, from the other side of the same relationship — including the
      # part that makes it expensive: the abort lands AFTER the listings are gone,
      # so the database is left HALF-WIPED. The e2e fixtures vanish, the seed
      # never runs, and every Maestro flow afterwards drives stale data while the
      # rig still reports "seed verified" because the personas can still log in.
      # That is what happened here: one save on listing 1076 by a non-e2e account
      # (anyone tapping the heart while testing) silently disabled the whole rig.
      #
      # `.or()` on both sides, matching what ListingView and HiddenListing above
      # already do.
      SavedListing.where(listing_id: listing_ids)
                  .or(SavedListing.where(user_id: user_ids))
                  .delete_all
      Listing.where(id: listing_ids).delete_all

      # USER-SCOPED tables that nothing else cleans up. Missing these aborts the
      # wipe with `PG::ForeignKeyViolation ... "fk_rails_63c5382842" on table
      # "saved_searches"` — and because the abort happens AFTER the listings are
      # gone, the database is left half-wiped: the e2e fixtures vanish and every
      # later flow fails on a missing fixture rather than on a broken seed. That
      # is a nasty failure to diagnose from the flow side, so the whole set is
      # enumerated here rather than discovered one constraint at a time.
      #
      # Checked against the schema: conversations, messages, saved_listings,
      # listing_views, hidden_listings, listing_price_histories, transactions and
      # reviews are either handled above or cascade at the database level. These
      # two are the ones that do not.
      SavedSearch.where(user_id: user_ids).delete_all
      UserWarning.where(user_id: user_ids).delete_all

      users.delete_all

      puts "  wiped #{E2E_EMAILS.length} users and all associated data"
      puts ""

      load Rails.root.join("db/seeds/e2e.rb")
    end
  end
end
