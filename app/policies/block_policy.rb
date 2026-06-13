class BlockPolicy < ApplicationPolicy
  # Any authenticated user can block or unblock another user (they are the blocker)
  def create? = record.blocker == user
  def destroy? = record.blocker == user

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(blocker: user)
    end
  end
end
