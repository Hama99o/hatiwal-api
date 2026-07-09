class ReviewSerializer < ApplicationSerializer
  fields :id, :rating, :comment, :role, :visible, :revealed_at, :created_at

  field(:transaction_id) { |r| r.transaction_id }
  field(:reviewee_id)    { |r| r.reviewee_id }

  # The author's identity — safe to expose because the public index only ever
  # returns VISIBLE reviews; a hidden review is only rendered back to its own
  # author (on create), who already knows who they are.
  field(:reviewer) do |r|
    u = r.reviewer
    { id: u.id, name: u.full_name, avatar_url: u.avatar.attached? ? u.avatar.url : nil }
  end
end
