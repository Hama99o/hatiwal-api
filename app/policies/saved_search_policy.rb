class SavedSearchPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def destroy?
    owner?
  end

  def mark_seen?
    owner?
  end

  private

  def owner?
    user.present? && record.user_id == user.id
  end
end
