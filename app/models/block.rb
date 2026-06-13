class Block < ApplicationRecord
  belongs_to :blocker, class_name: User.name
  belongs_to :blocked, class_name: User.name

  validates :blocker_id, uniqueness: { scope: :blocked_id }
  validate :cannot_block_yourself

  private

  def cannot_block_yourself
    errors.add(:blocked_id, "cannot block yourself") if blocker_id == blocked_id
  end
end
