class BlockPolicy < ApplicationPolicy
  # Any authenticated user can block or unblock another user (they are the blocker)
  # — except the Support account: a blocked Support thread would leave the user
  # unable to reach help, and the clients hide Block on support threads anyway.
  def create? = record.blocker == user && !record.blocked&.support_account?
  def destroy? = record.blocker == user

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(blocker: user)
    end
  end
end
