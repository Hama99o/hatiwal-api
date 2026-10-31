# IDEA-6 (docs/SAFE_MEETUP_SPOTS.md): the busy public places the meetup sheet
# suggests. Every active spot (a few dozen rows); the client keeps the ones near
# the listing and caches the list for offline use.
class Api::V1::MeetupSpotsController < Api::V1::BaseController
  skip_before_action :authenticate_user!, only: [ :index ]

  def index
    authorize MeetupSpot, :index?
    expires_in 1.hour, public: true
    render_blue_collection(MeetupSpotSerializer, policy_scope(MeetupSpot))
  end
end
