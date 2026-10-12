# Trigram indexes for the listing search (`Listing.search`: LOWER(title) LIKE
# '%word%' OR LOWER(description) LIKE '%word%'). A leading-wildcard LIKE cannot
# use a btree, so every search read the whole listings table.
# pg_trgm ships with Postgres and is a trusted extension (PG 13+): the database
# owner can enable it, no superuser needed. docs/PERFORMANCE_100K.md.
class EnablePgTrgm < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
  end
end
