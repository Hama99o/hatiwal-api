class Api::V1::Users::SavedSearchesController < Api::V1::BaseController
  before_action :authenticate_user!

  def index
    authorize SavedSearch
    saved_searches = current_user.saved_searches.recent.limit(SavedSearch::MAX_PER_USER)
    render_blue_collection(SavedSearchSerializer, saved_searches)
  end

  def create
    authorize SavedSearch
    saved_search = current_user.saved_searches.new(saved_search_params)

    if saved_search.save
      saved_search.dedupe_siblings!
      SavedSearch.prune_for(current_user)
      render_blue(SavedSearchSerializer, saved_search, status: :created)
    else
      render_unprocessable_entity(saved_search)
    end
  end

  def destroy
    saved_search = SavedSearch.find(params[:id])
    authorize saved_search

    if saved_search.destroy
      head :no_content
    else
      render_unprocessable_entity(saved_search)
    end
  end

  # PUT /api/v1/users/saved_searches/:id/mark_seen
  # Resets the new-matches badge by stamping last_viewed_at = now.
  def mark_seen
    saved_search = SavedSearch.find(params[:id])
    authorize saved_search, :mark_seen?

    saved_search.update!(last_viewed_at: Time.current)
    render_blue(SavedSearchSerializer, saved_search)
  end

  private

  def saved_search_params
    params.permit(:location, :category_id, :price_min, :price_max, :latitude, :longitude, :radius)
  end
end
