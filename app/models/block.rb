class Block < ApplicationRecord
  belongs_to :blocker, class_name: User.name
  belongs_to :blocked, class_name: User.name
  # privacy-b: made from a shop's page / chat; `blocked` is its owner.
  belongs_to :shop, class_name: Shop.name, optional: true

  validates :blocker_id, uniqueness: { scope: :blocked_id }
  validate :cannot_block_yourself

  private

  def cannot_block_yourself
    errors.add(:blocked_id, "cannot block yourself") if blocker_id == blocked_id
  end
end
