# Saved-search alerts (docs/SAVED_SEARCH_ALERTS.md, 1.2.1): the keyword and the
# opt-in on saved searches, the batching state, the account switch + daily cap,
# and one row per (search, listing) announced.
class AddSavedSearchAlerts < ActiveRecord::Migration[8.1]
  def change
    change_table :saved_searches, bulk: true do |t|
      t.string   :query
      t.boolean  :alert, default: false, null: false
      t.integer  :pending_alert_count, default: 0, null: false
      t.datetime :last_alerted_at
      t.datetime :alert_scheduled_at
      t.index %i[alert category_id]
    end

    change_table :users, bulk: true do |t|
      t.boolean :saved_search_alerts, default: true, null: false
      t.date    :alert_pushes_on
      t.integer :alert_pushes_count, default: 0, null: false
    end

    create_table :saved_search_alert_hits do |t|
      t.references :saved_search, null: false, foreign_key: { on_delete: :cascade }
      t.references :listing, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :alerted_at
      t.timestamps
      t.index %i[saved_search_id listing_id], unique: true
    end
  end
end
