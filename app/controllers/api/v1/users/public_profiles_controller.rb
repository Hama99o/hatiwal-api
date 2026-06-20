class Api::V1::Users::PublicProfilesController < Api::V1::BaseController
  def show
    # publicly_active: no public profile for an account that is deleted OR
    # pending deletion (in its grace window).
    user = User.publicly_active.find(params[:id])
    render_blue(UserSerializer, user, view: :public, options: { current_user: current_user })
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
