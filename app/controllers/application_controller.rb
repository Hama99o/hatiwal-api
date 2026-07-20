class ApplicationController < ActionController::API
  include DeviseTokenAuth::Concerns::SetUserByToken
  include Pundit::Authorization
  include Pagy::Backend

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  # Malformed params (e.g. a non-multipart body parsed as url-encoded, or a
  # nested-key type conflict) must be a clean 400 — not a 500. Rails only maps
  # the base ParseError to :bad_request by exact class name, so its ParamBuilder
  # subclasses (ParameterTypeError/InvalidParameterError) would otherwise 500.
  rescue_from ActionDispatch::ParamError, with: :render_bad_request

  before_action :set_active_storage_url_options

  private

  # Optional auth for public (guest-browsable) endpoints: resolves current_user
  # when a valid token is present, but never returns 401 for signed-out guests.
  def authenticate_optional!
    set_user_by_token
  rescue StandardError
    nil
  end

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

  # Largest page[size] a client may request (guards against abusive limits).
  MAX_PAGE_SIZE = 100

  # Pagy options from JSON:API-style params: page[number] plus an OPTIONAL
  # page[size] (clamped to 1..MAX_PAGE_SIZE; falls back to Pagy's default limit
  # when absent). Both the web and mobile clients send page[size] and expect it
  # honored — e.g. the web chat thread requests 50 messages/page and the seller
  # grids request 24 — so it must not be silently ignored.
  def pagy_page_options
    raw_page = params[:page]
    if raw_page.is_a?(ActionController::Parameters)
      page_num = raw_page[:number].to_i
      page_size = raw_page[:size].to_i
    else
      page_num = raw_page.to_i
      page_size = 0
    end
    opts = { page: page_num < 1 ? 1 : page_num }
    # Pagy 8.x's per-page var is `:items` (`pagy.items`); pass it explicitly so
    # the size is honored. (Pagy also reads `page:` from us so it doesn't choke
    # on the nested params[:page] hash.)
    opts[:items] = page_size.clamp(1, MAX_PAGE_SIZE) if page_size.positive?
    opts
  end

  def paginate_blue(serializer, collection, extra: {})
    pagy, records = pagy(collection, **pagy_page_options)
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

  # Like paginate_blue but applies a transform block to the paginated records
  # before serializing. Use when you need a post-pagination filter/map (e.g.
  # filter_map(&:listing) on a join-model relation) while keeping Pagy's
  # pagination metadata accurate at the SQL level.
  #
  #   paginate_blue_with_transform(ListingSerializer, saved_relation, extra: { view: :list }) do |page|
  #     page.filter_map(&:listing)
  #   end
  def paginate_blue_with_transform(serializer, collection, extra: {}, &transform)
    pagy, paged_records = pagy(collection, **pagy_page_options)
    records = block_given? ? transform.call(paged_records) : paged_records
    render json: {
      serializer.model_name.plural => serializer.render_as_hash(records, view: extra[:view] || :default, **extra.except(:view)),
      meta: {
        pagination: {
          current_page: pagy.page,
          next_page:    pagy.next,
          prev_page:    pagy.prev,
          total_count:  pagy.count,
          total_pages:  pagy.pages
        }
      }
    }
  end

  # Accepts either an ActiveRecord model (renders its validation errors array)
  # or a plain String/Exception (renders a single error message).
  def render_unprocessable_entity(record_or_message)
    body = if record_or_message.respond_to?(:errors)
             { errors: record_or_message.errors.full_messages }
    else
             { error: record_or_message.to_s }
    end
    render json: body, status: :unprocessable_entity
  end

  def render_not_found
    render json: { error: "Not found" }, status: :not_found
  end

  def render_forbidden
    render json: { error: "Forbidden" }, status: :forbidden
  end

  # Rejects a suspended/banned user on authenticated requests with a clear,
  # localized message + the admin's reason, so the app can tell them why they
  # are blocked. No-op for guests (current_user nil) and active users. New
  # logins are separately blocked by User#active_for_authentication?.
  def reject_blocked_user!
    return unless current_user&.account_blocked?

    render json: {
      error:   "account_#{current_user.status}",
      status:  current_user.status,
      message: current_user.account_block_message,
      reason:  current_user.block_reason
    }, status: :forbidden
  end

  def render_bad_request
    render json: { error: "Bad request" }, status: :bad_request
  end

  # General-purpose success helper for actions that return a small bespoke
  # payload that does not map to a serializer resource (e.g. { saved: true }).
  def render_ok(payload, status: :ok)
    render json: payload, status: status
  end
end
