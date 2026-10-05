# LOC-1 — PATCH /api/v1/users/me/location_guess
#
# A clue about where the signed-in user is: the area they searched in, or a GPS
# fix the app already had permission for (a listing's location is recorded by
# the listing create/update itself). The newest clue replaces the last.
#
# Always 204 on a well-formed clue, saved or not: when the user has an own
# address, or the point is outside Afghanistan/Pakistan/Iran, the clue is
# simply ignored (User#record_location_guess!). The client reads the result
# from `location` on GET /users/me and never needs to know which happened.
class Api::V1::Users::LocationGuessesController < Api::V1::BaseController
  # The app sends one per search-area change and at most one GPS fix a day;
  # this is only there to stop a script from writing on every frame.
  throttle to: 60, within: 1.hour, by: :user, only: :update

  def update
    authorize current_user, :update_location_guess?
    return render_unprocessable_entity("Unknown location source") unless User::GuessSource::ALL.include?(guess_params[:source].to_s)
    return render_unprocessable_entity("Latitude and longitude are required") unless coordinates?

    current_user.record_location_guess!(
      latitude: guess_params[:latitude], longitude: guess_params[:longitude],
      source: guess_params[:source], province: guess_params[:province]
    )
    head :no_content
  end

  private

  def guess_params
    params.permit(:latitude, :longitude, :province, :source)
  end

  def coordinates?
    lat = Float(guess_params[:latitude], exception: false)
    lng = Float(guess_params[:longitude], exception: false)
    lat.present? && lng.present? && lat.between?(-90, 90) && lng.between?(-180, 180)
  end
end
