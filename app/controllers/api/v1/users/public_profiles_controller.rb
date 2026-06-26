class Api::V1::Users::PublicProfilesController < Api::V1::BaseController
  # Guests can view a seller's public profile without logging in — this is the
  # primary entry point for shareable deep links (hatiwal://seller/:id).
  # Authenticated users still get the full view (blocked flag, etc.).
  skip_before_action :authenticate_user!
  skip_before_action :reject_blocked_user!
  before_action :authenticate_optional!

  def show
    # publicly_active: no public profile for an account that is deleted OR
    # pending deletion (in its grace window).
    user = User.publicly_active.find(params[:id])
    render_blue(UserSerializer, user, view: :public, options: { current_user: current_user })
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
