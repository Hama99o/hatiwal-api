class AddNameUrToCategories < ActiveRecord::Migration[8.0]
  # Urdu (ur) becomes the 4th supported locale when Hatiwal opens to Pakistan.
  #
  # NULLABLE on purpose, unlike name_en/name_ps/name_fa which are NOT NULL. The
  # table already holds rows written before Urdu existed, and an operator adding
  # a category from /admin/categories must not be blocked because they cannot
  # write Urdu. Category#name_for("ur") falls back to name_en when this is blank,
  # so a missing translation degrades to English rather than to an empty label.
  def change
    add_column :categories, :name_ur, :string
  end
end
