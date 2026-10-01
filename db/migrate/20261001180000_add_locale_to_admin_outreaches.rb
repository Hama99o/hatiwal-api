# Which language version a one-to-one send delivered (Messages now writes all
# four languages and each person gets theirs). Additive.
class AddLocaleToAdminOutreaches < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_outreaches, :locale, :string
  end
end
