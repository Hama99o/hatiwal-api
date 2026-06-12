class Api::V1::CategoriesController < Api::V1::BaseController
  def index
    categories = Category.active.ordered
    render json: { categories: CategorySerializer.render_as_hash(categories) }, status: :ok
  end
end
