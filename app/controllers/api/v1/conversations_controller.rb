class Api::V1::ConversationsController < Api::V1::BaseController
  before_action :set_listing, only: [ :create ]
  before_action :set_conversation, only: [ :show ]

  def index
    conversations = policy_scope(Conversation.for_user(current_user.id).ordered)
    paginate_blue(ConversationSerializer, conversations, extra: { view: :list })
  end

  def show
    render_blue(ConversationSerializer, @conversation, view: :detailed)
  end

  def create
    authorize @listing, :start_conversation?

    service = Conversations::StartService.new(
      buyer: current_user,
      listing: @listing,
      message_body: params[:message]
    )

    conversation = service.call
    render_blue(ConversationSerializer, conversation, view: :detailed, status: :created)
  rescue Conversations::StartService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_listing
    @listing = Listing.find(params[:listing_id])
  end

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:id])
  end
end
