class MessagePolicy < ApplicationPolicy
  # Only the message's author may soft-delete it.
  def destroy?
    record.user_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
