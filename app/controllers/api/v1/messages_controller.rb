class Api::V1::MessagesController < Api::V1::BaseController
  before_action :set_conversation

  def index
    authorize @conversation, :read_messages?
    messages = @conversation.messages.ordered
    paginate_blue(MessageSerializer, messages, extra: { view: :default })
  end

  def create
    authorize @conversation, :send_message?

    @message = @conversation.messages.new(
      user: current_user,
      body: params[:body],
      kind: params[:kind] || :text
    )

    if @message.save
      render_blue(MessageSerializer, @message, view: :default, status: :created)
    else
      render_unprocessable_entity(@message)
    end
  end

  def mark_read
    authorize @conversation, :read_messages?
    @conversation.messages.where(read_at: nil).where.not(user: current_user).find_each(&:mark_read!)
    head :no_content
  end

  private

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:conversation_id])
  end
end
