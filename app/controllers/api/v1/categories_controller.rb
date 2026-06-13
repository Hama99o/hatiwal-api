class Api::V1::CategoriesController < Api::V1::BaseController
  def index
    authorize Category, :index?
    categories = Category.active.ordered.top_level.includes(:subcategories)
    render json: {
      categories: CategorySerializer.render_as_hash(categories, view: :with_subcategories)
    }, status: :ok
  end
end
