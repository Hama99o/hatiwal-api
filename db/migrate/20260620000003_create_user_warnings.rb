class CreateUserWarnings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_warnings do |t|
      t.references :user, null: false, foreign_key: true
      # Issuing admin (accountability). Nullable so a warning survives if the
      # admin account is ever removed.
      t.references :admin_user, null: true, foreign_key: true
      t.integer  :category, null: false, default: 0
      t.string   :reason, null: false
      # When this warning stops counting toward the block threshold (decay).
      t.datetime :expires_at, null: false
      # When the user acknowledged seeing it in the app.
      t.datetime :acknowledged_at

      t.timestamps
    end

    add_index :user_warnings, [ :user_id, :expires_at ]
  end
end
