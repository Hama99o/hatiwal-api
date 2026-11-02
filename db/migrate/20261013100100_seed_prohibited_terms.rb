# Data: the starting prohibited-term list (config/prohibited_terms.yml) on
# every database that runs migrations, production included. INSERT ... ON
# CONFLICT DO NOTHING: only adds missing rows, never edits or deletes, so it is
# safe to run again. No listing is read or changed here: existing listings are
# NOT scanned (a flag opens on the next publish / edit).
class SeedProhibitedTerms < ActiveRecord::Migration[8.1]
  def up
    ProhibitedTerm.reset_column_information
    say "prohibited_terms: #{ProhibitedTerm.seed_defaults!} added"
  end

  def down
    # The admin may have edited the list since; leave it as it is.
  end
end
