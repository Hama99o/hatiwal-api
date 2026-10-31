# IDEA-9: a chunked upload is its user's alone. Others never find it (the scope) — 404, never 403, so an id
# leaks nothing.
class ResumableUploadPolicy < ApplicationPolicy
  def create? = user.present?
  def show? = owner?
  def update? = owner? && record.open?

  class Scope < ApplicationPolicy::Scope
    def resolve = user ? scope.where(user_id: user.id) : scope.none
  end

  private

  def owner? = user.present? && record.user_id == user.id
end
