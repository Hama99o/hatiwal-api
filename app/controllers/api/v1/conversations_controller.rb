class Api::V1::ConversationsController < Api::V1::BaseController
  # Allowed values for the `role` index param (TASK-R517) — "conversations
  # where I am buying" vs "conversations where I am selling". A frozen
  # constant so the branch below never compares against bare string literals.
  ROLES = { buying: "buying", selling: "selling" }.freeze

  before_action :set_listing, only: [ :create ]

  # Opening a conversation is how you reach a stranger's inbox, so it is the
  # spam vector: one account messaging every seller in the city. Only NEW
  # threads are limited — replies inside an existing thread go through
  # MessagesController, which has its own, much higher limit.
  throttle to: 30, within: 1.day, by: :user, only: :create
  before_action :set_conversation, only: [ :show ]
  before_action :set_conversation_for_mutation, only: [ :destroy, :mark_read, :mark_unread, :archive, :unarchive ]

  def index
    # Default: show non-archived conversations. ?archived=true shows archived ones.
    show_archived = ActiveModel::Type::Boolean.new.cast(params[:archived])

    base_scope = show_archived \
      ? Conversation.for_user(current_user.id).not_deleted_for(current_user).archived_for(current_user) \
      : Conversation.for_user(current_user.id).not_deleted_for(current_user).not_archived_for(current_user)

    base_scope = apply_role_filter(base_scope)

    # ?search= — the WHOLE inbox, not just the page the client happens to hold.
    #
    # Owner, 2026-09-02: "the message conversation search is not working, it's
    # not connected with backend, it's not search in db". Correct: the clients
    # filtered already-loaded items in memory, so a match on page 3 did not
    # exist as far as the user was concerned.
    #
    # Applied BEFORE ordering and pagination, so page 1 of a search is the best
    # matches — not "the matches that happened to be on page 1 anyway".
    base_scope = base_scope.matching(params[:search]) if params[:search].present?

    conversations = policy_scope(
      base_scope.ordered
                .includes(
                    # :latest_message loads only the newest message per conversation
                    # (has_one with ORDER BY DESC) instead of the entire messages
                    # collection — far lighter than the old includes(:messages) path.
                    :latest_message,
                    { listing: { images_attachments: { blob: { variant_records: { image_attachment: :blob } } } },
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
    updated = Message.where(id: latest_inbound).update_all(read_at: nil)

    # Nothing to mark. On a conversation where the other party never replied there
    # is no inbound message, so the UPDATE touches 0 rows — and this used to still
    # answer 204. The client took that as success, and since the row menu offers
    # "Mark as unread" whenever unread is 0 (always true here), a user could tap it
    # forever with nothing happening and no error to explain why. Say so instead:
    # the mobile client already rolls back and shows its error toast on a non-2xx.
    return render_unprocessable_entity("Nothing to mark as unread — this conversation has no messages from the other person") if updated.zero?

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

  # Applies the `role` index param, when it is a recognised value, to narrow
  # the inbox to just the caller's buyer threads or just their seller threads.
  # Any absent or unrecognised value is a no-op — the full mixed inbox is the
  # existing (and default) behaviour, never a 500 or an accidentally-empty list.
  def apply_role_filter(scope)
    case params[:role]
    when ROLES[:buying]
      scope.as_buyer_for(current_user)
    when ROLES[:selling]
      scope.as_seller_for(current_user)
    else
      scope
    end
  end

  def set_listing
    @listing = Listing.find(params[:listing_id])
  end

  def set_conversation
    # TASK-K729: eager-load the listing's category (reserved/sold recovery
    # notice's "Browse similar in {category}" CTA) AND its sale_transactions
    # (Listing#current_sale, used by viewer_is_sale_buyer below) so both stay
    # query-flat — without this, current_sale would fire a fresh query.
    @conversation = policy_scope(Conversation).includes(listing: [ :category, :sale_transactions ]).find(params[:id])
  end

  def set_conversation_for_mutation
    @conversation = Conversation.find(params[:id])
  end
end
