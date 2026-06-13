class Api::V1::Users::PublicProfilesController < Api::V1::BaseController
  def show
    user = User.find(params[:id])
    render_blue(UserSerializer, user, view: :public)
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
