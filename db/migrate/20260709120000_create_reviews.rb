class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :transaction, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.references :reviewee, null: false, foreign_key: { to_table: :users }
      t.integer :role, null: false
      t.integer :rating, null: false
      t.text :comment
      # Double-blind: a review stays hidden until the counterparty also submits
      # (revealed together) or REVEAL_WINDOW elapses (RevealOverdueReviewsJob).
      t.boolean :visible, null: false, default: false
      t.datetime :revealed_at

      t.timestamps
    end

    # One review per person per sale — no re-rating to inflate a score.
    add_index :reviews, [ :transaction_id, :reviewer_id ], unique: true,
                                                            name: "index_reviews_unique_per_reviewer_per_txn"
    # Drives the public "visible reviews for this user" list + stat recompute.
    add_index :reviews, [ :reviewee_id, :visible ]
  end
end
