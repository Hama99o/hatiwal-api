class Api::V1::Users::ProfilesController < Api::V1::BaseController
  before_action :set_user, only: [ :show ]

  def me
    render_blue(UserSerializer, current_user, view: :me)
  end

  def update_me
    if current_user.update(profile_params)
      render_blue(UserSerializer, current_user, view: :me)
    else
      render_unprocessable_entity(current_user)
    end
  end

  def show
    render_blue(UserSerializer, @user, view: :public)
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def profile_params
    params.require(:user).permit(
      :firstname, :lastname, :phone, :bio,
      :city, :province, :latitude, :longitude,
      :preferred_language, :seller_mode, :avatar
    )
  end
end
