class Api::V1::MessagesController < Api::V1::BaseController
  before_action :set_conversation
  before_action :set_message, only: [ :destroy ]

  def index
    authorize @conversation, :read_messages?
    # Newest-first so page 1 is the MOST RECENT messages — correct for a chat
    # that opens at the bottom and loads older messages as you scroll up. The
    # mobile client reverses each page for chronological display and prepends
    # older pages on scroll-up.
    messages = @conversation.messages
                           .includes(user: { avatar_attachment: :blob },
                                     attachment_attachment: :blob)
                           .newest_first
    paginate_blue(MessageSerializer, messages, extra: { view: :default })
  end

  def create
    authorize @conversation, :send_message?

    @message = @conversation.messages.new(safe_message_params)
    @message.user = current_user
    @message.attachment = params[:attachment] if params[:attachment].present?

    if @message.save
      BroadcastMessageJob.perform_later(@message.id)   # in-app real-time (open app)
      SendMessagePushJob.perform_later(@message.id)     # push notification (closed app)
      render_blue(MessageSerializer, @message, view: :default, status: :created)
    else
      render_unprocessable_entity(@message)
    end
  end

  def destroy
    authorize @message
    @message.soft_delete!
    BroadcastMessageJob.perform_later(@message.id) # real-time tombstone flip for the other participant
    render_blue(MessageSerializer, @message, view: :default)
  end

  def mark_read
    authorize @conversation, :read_messages?
    @conversation.messages
                 .where(read_at: nil)
                 .where.not(user: current_user)
                 .update_all(read_at: Time.current)
    head :no_content
  end

  private

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:conversation_id])
  end

  def set_message
    @message = @conversation.messages.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  # Builds permitted params and enforces the kind whitelist.
  #
  # - No :kind supplied             → defaults to :text
  # - Kind in USER_SENDABLE_KINDS   → accepted as-is
  # - Any other value (incl. "system") → coerced to :system so the model
  #   validation `kind_must_not_be_system_when_user_authored` fires and the
  #   caller receives a 422.  This avoids raising an ArgumentError on an
  #   unrecognised enum string while still rejecting the request cleanly.
  def safe_message_params
    permitted = params.permit(:body, :responds_to_id)
    raw_kind  = params[:kind].presence

    permitted[:kind] = resolved_kind(raw_kind)
    permitted
  end

  def resolved_kind(raw_kind)
    return :text if raw_kind.nil?
    return raw_kind.to_sym if Message::USER_SENDABLE_KINDS.include?(raw_kind.to_s)

    # Coerce to :system — the model validation blocks this and returns 422.
    :system
  end
end
