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

  # POST /api/v1/users/me/restore — cancel a pending account deletion. The user
  # logged back in within the 30-day grace window and chose to keep their
  # account; restores their listings and clears the scheduled deletion.
  def restore
    if current_user.cancel_deletion!
      render_blue(UserSerializer, current_user, view: :me)
    else
      render_unprocessable_entity("Account is not scheduled for deletion")
    end
  end

  def show
    render_blue(UserSerializer, @user, view: :public, options: { current_user: current_user })
  end

  private

  def set_user
    # publicly_active: a deleted or pending-deletion account has no public profile
    # (RecordNotFound → 404 via the global rescue).
    @user = User.publicly_active.find(params[:id])
  end

  def profile_params
    params.require(:user).permit(
      :firstname, :lastname, :phone, :bio,
      :city, :province, :latitude, :longitude,
      :preferred_language, :seller_mode, :preferred_theme, :avatar,
      :push_token, :away_until
    )
  end
end
