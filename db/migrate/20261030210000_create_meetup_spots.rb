# IDEA-6 (docs/SAFE_MEETUP_SPOTS.md): busy public places suggested when two
# people arrange a meetup. Admin-edited; a row shows in the apps only once
# `active`. `needs_local_check` marks the draft rows nobody local confirmed yet.
class CreateMeetupSpots < ActiveRecord::Migration[8.1]
  def change
    create_table :meetup_spots do |t|
      t.string :city_key, null: false
      t.string :name_en, null: false
      t.string :name_ps
      t.string :name_fa
      t.string :name_ur
      t.integer :kind, null: false, default: 0
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: false
      t.boolean :needs_local_check, null: false, default: true
      t.text :note
      t.timestamps
    end
    add_index :meetup_spots, %i[city_key name_en], unique: true
    add_index :meetup_spots, %i[active city_key position]
  end
end
