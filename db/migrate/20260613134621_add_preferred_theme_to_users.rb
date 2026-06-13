class AddPreferredThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_theme, :string, default: "system"
  end
end
