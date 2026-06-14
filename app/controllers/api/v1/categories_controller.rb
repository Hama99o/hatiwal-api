class Api::V1::CategoriesController < Api::V1::BaseController
  # Public reference data — guests browsing the feed need the category chips.
  skip_before_action :authenticate_user!, only: [ :index ]
  before_action :authenticate_optional!, only: [ :index ]

  def index
    authorize Category, :index?
    categories = Category.active.ordered.top_level.includes(:subcategories)
    render json: {
      categories: CategorySerializer.render_as_hash(categories, view: :with_subcategories)
    }, status: :ok
  end
end
