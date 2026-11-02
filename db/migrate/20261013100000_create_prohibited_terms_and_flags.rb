# Prohibited items (owner, 2026-10-13, option B: ALL MANUAL). Two new tables,
# nothing existing is altered:
#   * prohibited_terms — the words an admin keeps (admin page "Prohibited terms").
#   * flags            — "an admin should look at this": opened by a matched
#                        term or a prohibited-item report, closed by an admin.
# A match never blocks or changes a listing; it only opens a flag.
class CreateProhibitedTermsAndFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :prohibited_terms do |t|
      # Stored normalized (ProhibitedItems::Normalizer.term); a trailing "*"
      # means "words starting with".
      t.string :term, null: false
      t.integer :locale, null: false, default: 3 # en 0, ps 1, fa 2, any 3
      t.integer :category, null: false
      t.text :note
      t.timestamps
    end
    add_index :prohibited_terms, %i[term locale], unique: true
    add_index :prohibited_terms, :category

    create_table :flags do |t|
      t.references :flaggable, polymorphic: true, null: false
      t.integer :source, null: false, default: 0 # term 0, report 1
      t.integer :status, null: false, default: 0 # open 0, dismissed 1, actioned 2
      t.integer :category
      t.string :matched_term
      t.references :prohibited_term, foreign_key: { on_delete: :nullify }
      t.references :acted_by, foreign_key: { to_table: :admin_users, on_delete: :nullify }
      t.string :action_taken
      t.text :note
      t.datetime :acted_at
      t.timestamps
    end
    # One OPEN flag per listing / shop: a second match or report joins it.
    add_index :flags, %i[flaggable_type flaggable_id], unique: true, where: "status = 0",
                                                       name: "index_flags_one_open_per_flaggable"
    add_index :flags, %i[status created_at]
  end
end
