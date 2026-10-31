# IDEA-6: the suggested meetup spots are public reference data (a guest can
# read them); only admins edit them (Admin::MeetupSpotPolicy).
class MeetupSpotPolicy < ApplicationPolicy
  def index?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.shown
    end
  end
end
