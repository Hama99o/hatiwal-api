class ConversationPolicy < ApplicationPolicy
  def show?          = participant?
  def destroy?       = participant?
  def read_messages? = participant?
  def send_message?  = participant? && record.open?

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.for_user(user.id)
    end
  end

  private

  def participant? = record.participant?(user)
end
