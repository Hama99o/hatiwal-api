# LOC-1 — where the app GUESSES a user lives, from what they do (a listing they
# post, an area they search, GPS already permitted). Kept apart from the user's
# OWN address (latitude/longitude/province/city), which only the user sets and a
# guess never overwrites. Never serialized publicly.
class AddGuessedLocationToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.decimal :guessed_latitude, precision: 10, scale: 6
      t.decimal :guessed_longitude, precision: 10, scale: 6
      t.string :guessed_province
      t.string :guessed_source
      t.datetime :guessed_at
    end
  end
end
