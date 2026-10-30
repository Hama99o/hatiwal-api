class Api::V1::Users::ProfilesController < Api::V1::BaseController
  # OFFLINE §10.1: a retried write with the same Idempotency-Key runs once.
  idempotent :update_me

  before_action :set_user, only: [ :show ]
  # Hunt-2 (1.1.7): far above the app's own calls (push token, theme, language).
  throttle to: 120, within: 1.hour, by: :user, only: :update_me

  def me
    render_blue(UserSerializer, current_user, view: :me)
  end

  def update_me
    # Owner decision, 2026-10-08: once verified, a person stays verified — a
    # name change no longer drops the badge (drop_badge_after_name_change!).
    #
    # OFFLINE §10.2: with `base` (what the phone saw), a field changed on
    # another device meanwhile is not overwritten; the rest applies; 409.
    edit = Edits::WithBase.split(current_user, profile_params, profile_base)
    attrs = edit.attrs.to_h.stringify_keys
    # The push token belongs to the device that sent it (its devise client): only that client's sign-out clears it.
    attrs["push_token_client"] = (request.headers["client"] if attrs["push_token"].present?) if attrs.key?("push_token")
    if current_user.update(attrs)
      current_user.claim_push_token! if attrs["push_token"].present?
      return render_profile_conflict(edit.conflicts) if edit.conflicts.any?

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

  # Only what a person edits by hand can conflict (not the push token, prefs).
  PROFILE_BASE_FIELDS = %i[firstname lastname phone bio city province whatsapp_number].freeze

  def profile_base
    base = params.dig(:user, :base)
    base.respond_to?(:permit) ? base.permit(*PROFILE_BASE_FIELDS).to_h : {}
  end

  def render_profile_conflict(conflicts)
    render_ok({ user: UserSerializer.render_as_hash(current_user, view: :me), code: "edit_conflict", fields: conflicts },
              status: :conflict)
  end

  def profile_params
    params.require(:user).permit(
      :firstname, :lastname, :phone, :bio,
      :city, :province, :latitude, :longitude,
      :preferred_language, :seller_mode, :preferred_theme, :avatar,
      :push_token, :away_until,
      # Why the app could NOT get a push token, when it couldn't — shown on the
      # admin dashboard (ClientVersionReporting). Capped and normalized there.
      :push_registration_error,
      # Contact details and their visibility (owner request, 2026-09-02).
      :whatsapp_number, :show_phone_publicly, :show_address_publicly
    )
  end
end
