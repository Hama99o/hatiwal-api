# SHOP-3 invitations. The owner's side is ShopPolicy#manage_team?; this is the
# invited person's side: only invitations addressed to them, never anyone else's.
class ShopInvitePolicy < ApplicationPolicy
  def index? = user.present?

  class Scope < Scope
    def resolve = scope.addressed_to(user)
  end
end
