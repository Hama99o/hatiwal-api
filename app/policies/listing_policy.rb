class ListingPolicy < ApplicationPolicy
  def index?  = true
  def show?   = true
  def create? = true
  def save?   = true

  def update?  = owner?
  def destroy? = owner?
  def publish? = owner? && record.draft?
  def reserve? = owner? && record.active?
  def sold?    = owner? && record.reserved?

  def start_conversation?
    record.active? && !owner?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end

  private

  def owner? = record.user_id == user.id
end
