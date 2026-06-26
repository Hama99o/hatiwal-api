class Api::V1::ConversationsController < Api::V1::BaseController
  before_action :set_listing, only: [ :create ]
  before_action :set_conversation, only: [ :show ]
  before_action :set_conversation_for_mutation, only: [ :destroy, :mark_read, :mark_unread, :archive, :unarchive ]

  def index
    # Default: show non-archived conversations. ?archived=true shows archived ones.
    show_archived = ActiveModel::Type::Boolean.new.cast(params[:archived])

    base_scope = show_archived \
      ? Conversation.for_user(current_user.id).not_deleted_for(current_user).archived_for(current_user) \
      : Conversation.for_user(current_user.id).not_deleted_for(current_user).not_archived_for(current_user)

    conversations = policy_scope(
      base_scope.ordered
                .includes(
                    # :latest_message loads only the newest message per conversation
                    # (has_one with ORDER BY DESC) instead of the entire messages
                    # collection — far lighter than the old includes(:messages) path.
                    :latest_message,
                    { listing: { images_attachments: :blob },
                      buyer: { avatar_attachment: :blob },
                      seller: { avatar_attachment: :blob } }
                  )
    )
    conversations = conversations.where(listing_id: params[:listing_id]) if params[:listing_id].present?

    # Preload the current user's block relationships once (as id sets) so the
    # serializer's blocked_with_participant flag resolves in memory instead of
    # firing two block-existence queries per conversation row (N+1).
    blocked_ids = current_user.blocked_users.ids.to_set
    blocker_ids = current_user.blocking_users.ids.to_set

    # Compute unread counts for all visible conversations in a single GROUP BY
    # query and pass the resulting hash to the serializer so every row reads
    # from memory — no per-row COUNT queries (N+1).
    conversation_ids = conversations.map(&:id)
    unread_counts = Message
      .where(conversation_id: conversation_ids, read_at: nil)
      .where.not(user_id: current_user.id)
      .group(:conversation_id)
      .count

    paginate_blue(
      ConversationSerializer, conversations,
      extra: {
        view: :list, current_user: current_user,
        blocked_ids: blocked_ids, blocker_ids: blocker_ids,
        unread_counts: unread_counts
      }
    )
  end

  def show
    render_blue(ConversationSerializer, @conversation, view: :detailed, options: { current_user: current_user })
  end

  def destroy
    authorize @conversation
    @conversation.delete_for!(current_user)
    head :no_content
  end

  def mark_read
    authorize @conversation
    @conversation.messages
                 .where(read_at: nil)
                 .where.not(user_id: current_user.id)
                 .update_all(read_at: Time.current)
    head :no_content
  end

  def mark_unread
    authorize @conversation
    # Set read_at = nil on the most recent inbound message so that
    # unread_count_for(current_user) > 0 again.  A single targeted UPDATE
    # avoids N+1 — we find the latest inbound message id via a subquery and
    # update only that one row.
    latest_inbound = @conversation.messages
                                  .where.not(user_id: current_user.id)
                                  .order(created_at: :desc)
                                  .limit(1)
    Message.where(id: latest_inbound).update_all(read_at: nil)
    head :no_content
  end

  def archive
    authorize @conversation
    @conversation.archive_for!(current_user)
    head :no_content
  end

  def unarchive
    authorize @conversation
    @conversation.unarchive_for!(current_user)
    head :no_content
  end

  def create
    authorize @listing, :start_conversation?

    service = Conversations::StartService.new(
      buyer: current_user,
      listing: @listing,
      message_body: params[:message]
    )

    conversation = service.call
    render_blue(ConversationSerializer, conversation, view: :detailed, status: :created,
                                                      options: { current_user: current_user })
  rescue Conversations::StartService::Error => e
    render_unprocessable_entity(e)
  end

  private

  def set_listing
    @listing = Listing.find(params[:listing_id])
  end

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:id])
  end

  def set_conversation_for_mutation
    @conversation = Conversation.find(params[:id])
  end
end
