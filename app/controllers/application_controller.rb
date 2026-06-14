class ApplicationController < ActionController::API
  include DeviseTokenAuth::Concerns::SetUserByToken
  include Pundit::Authorization
  include Pagy::Backend

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  before_action :set_active_storage_url_options

  private

  def set_active_storage_url_options
    ActiveStorage::Current.url_options = {
      host:     request.host,
      port:     request.port,
      protocol: request.protocol
    }
  end

  def render_blue(serializer, record, view: :default, status: :ok, options: {})
    render json: { serializer.model_name.singular => serializer.render_as_hash(record, view: view, **options) }, status: status
  end

  # Render a non-paginated collection under the serializer's plural key.
  # Use for small, fixed-size lists (e.g. "the 5 most recent") where Pagy
  # pagination is unnecessary and would override an explicit `.limit`.
  def render_blue_collection(serializer, collection, view: :default, status: :ok, options: {})
    render json: { serializer.model_name.plural => serializer.render_as_hash(collection, view: view, **options) }, status: status
  end

  def paginate_blue(serializer, collection, extra: {})
    # params[:page] can arrive as a nested hash (e.g. page[size]=10 from some
    # JSON:API clients) — extract the integer page number safely.
    raw_page = params[:page]
    page_num = raw_page.is_a?(ActionController::Parameters) ? raw_page[:number].to_i : raw_page.to_i
    page_num = 1 if page_num < 1
    pagy, records = pagy(collection, page: page_num)
    render json: {
      serializer.model_name.plural => serializer.render_as_hash(records, view: extra[:view] || :default, **extra.except(:view)),
      meta: {
        pagination: {
          current_page: pagy.page,
          next_page: pagy.next,
          prev_page: pagy.prev,
          total_count: pagy.count,
          total_pages: pagy.pages
        }
      }
    }
  end

  def render_unprocessable_entity(record)
    render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_forbidden
    render json: { error: "Forbidden" }, status: :forbidden
  end
end
