class UserPolicy < ApplicationPolicy
  # LOC-1 — only the user themself can teach the app where they are.
  def update_location_guess? = record == user
end
