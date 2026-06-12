class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reportable, polymorphic: true, null: false
      t.integer :reason, null: false
      t.text :description
      t.integer :status, default: 0, null: false

      t.timestamps
    end

    add_index :reports, [:reporter_id, :reportable_type, :reportable_id], unique: true, name: "idx_reports_unique_per_reporter"
    add_index :reports, :status
  end
end
