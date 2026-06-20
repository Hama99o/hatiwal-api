class CreateAdminUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :name

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable — who signed in, when, from where (security audit trail)
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Lockable — lock the account after repeated failed attempts
      t.integer  :failed_attempts, default: 0, null: false
      t.string   :unlock_token
      t.datetime :locked_at

      t.timestamps null: false
    end

    add_index :admin_users, :email,                unique: true
    add_index :admin_users, :reset_password_token, unique: true
    add_index :admin_users, :unlock_token,         unique: true
  end
end
