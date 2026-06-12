class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :firstname, :string, null: false, default: ""
    add_column :users, :lastname, :string, null: false, default: ""
    add_column :users, :phone, :string
    add_column :users, :bio, :string
    add_column :users, :city, :string
    add_column :users, :province, :string
    add_column :users, :latitude, :decimal, precision: 10, scale: 6
    add_column :users, :longitude, :decimal, precision: 10, scale: 6
    add_column :users, :status, :integer, default: 0, null: false
    add_column :users, :preferred_language, :string, default: "ps"

    add_index :users, :status
    add_index :users, :city
  end
end
