# Indexes for the hot read paths at 100k users (docs/PERFORMANCE_100K.md).
# All CONCURRENTLY: building them never locks listings or users for writes.
class AddFeedAndSearchIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # `Listing.from_active_sellers` is `user_id NOT IN (SELECT id FROM users
    # WHERE status != 0)`, on EVERY public listing query. `!=` cannot use the
    # status btree, so each feed query scanned all users (~85 ms at 100k users,
    # up to 4 times per request). Only banned/suspended users are in this index.
    add_index :users, :id, where: "status <> 0", name: "index_users_on_id_not_active",
                           algorithm: :concurrently

    # The browsable feed: live (active/reserved) and not removed — the static
    # part of `Listing.browsable`, in feed order. INCLUDE carries the columns the
    # other feed filters read, so the feed's total count (pagination meta) is an
    # index-only scan instead of a scan of the whole table.
    add_index :listings, :bumped_at, order: { bumped_at: :desc },
                                     include: %i[user_id shop_id expires_at category_id price],
                                     where: "status IN (1, 2) AND removed_at IS NULL",
                                     name: "index_listings_browsable_feed",
                                     algorithm: :concurrently

    # Listing.search — trigram GIN on exactly the expressions it filters on.
    add_index :listings, "lower((title)::text) gin_trgm_ops", using: :gin,
                                                              name: "index_listings_on_lower_title_trgm",
                                                              algorithm: :concurrently
    add_index :listings, "lower(description) gin_trgm_ops", using: :gin,
                                                            name: "index_listings_on_lower_description_trgm",
                                                            algorithm: :concurrently

    # Postgres keeps statistics for an expression index only after the table is
    # analysed. Without them the planner ignored the trigram indexes and a search
    # with no match took 2.2 s instead of 30 ms (measured on the 300k-listing
    # scratch DB). Autoanalyze would only get there after ~10% of rows change.
    reversible { |dir| dir.up { execute "ANALYZE listings, users" } }
  end
end
