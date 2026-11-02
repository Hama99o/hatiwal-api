# Any signed-in, unblocked user may open their own chat connection (the base
# controller has already refused a guest and a suspended or banned account).
class CableTicketPolicy < ApplicationPolicy
  def create? = user.present?
end
