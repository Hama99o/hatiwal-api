class ConversationPolicy < ApplicationPolicy
  def show?          = participant?
  def destroy?       = participant?
  def read_messages? = participant?
  def send_message?  = participant? && record.open? && !blocked_pair?
  def mark_read?     = participant?
  def mark_unread?   = participant?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.for_user(user.id)
    end
  end

  private

  def participant? = record.participant?(user)

  # Returns true if either participant has blocked the other.
  # Uses Conversation#other_participant so we never hard-code buyer/seller roles.
  def blocked_pair?
    other = record.other_participant(user)
    return false if other.nil?

    user.blocked?(other) || user.blocked_by?(other)
  end
end
