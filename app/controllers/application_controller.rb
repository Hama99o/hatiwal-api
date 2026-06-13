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

  def paginate_blue(serializer, collection, extra: {})
    pagy, records = pagy(collection)
    render json: {
      serializer.model_name.plural => serializer.render_as_hash(records, view: extra[:view] || :default),
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
