class Api::V1::MessagesController < Api::V1::BaseController
  # OFFLINE §10.1: a retried write with the same Idempotency-Key runs once.
  idempotent :create, :destroy

  before_action :set_conversation
  before_action :set_message, only: [ :destroy ]

  # Deliberately high: this is a chat, and haggling over a price is a burst of
  # short messages. It exists only to stop a script from using the thread as a
  # firehose (every message also enqueues a broadcast AND a push job).
  throttle to: 120, within: 1.hour, by: :user, only: :create
  # Voice messages (1.2.1) also count here: each one runs ffmpeg in the request.
  throttle to: 60, within: 1.hour, by: :user, only: :create, if: -> { params[:kind].to_s == "voice_message" }

  # English fallbacks; the apps show their own en/ps/fa/ur text for each code.
  VOICE_REFUSALS = {
    voice_missing:   "Record a voice message to send.",
    voice_too_large: "This voice message is too large (2 MB max).",
    voice_too_short: "Voice messages need at least 1 second.",
    voice_too_long:  "Voice messages are up to 2 minutes.",
    voice_invalid:   "This file is not a voice recording we can play."
  }.freeze
  VOICE_UNAVAILABLE = "Voice messages are not available right now.".freeze
  VOICE_BUSY = "Busy, sending again in a moment.".freeze
  # Seconds; about one 2-minute clip's transcode on the production VPS.
  VOICE_BUSY_RETRY_AFTER = 5

  def index
    authorize @conversation, :read_messages?
    # Newest-first so page 1 is the MOST RECENT messages — correct for a chat
    # that opens at the bottom and loads older messages as you scroll up. The
    # mobile client reverses each page for chronological display and prepends
    # older pages on scroll-up.
    messages = @conversation.messages
                           .includes(user: { avatar_attachment: :blob },
                                     attachment_attachment: :blob,
                                     # sender as the shop (MessageSerializer): one load, not one per message
                                     conversation: [ { shop: { logo_attachment: :blob } }, { listing: { shop: { logo_attachment: :blob } } } ])
                           .newest_first
    paginate_blue(MessageSerializer, messages, extra: { view: :default, current_user: current_user })
  end

  def create
    # SHOP-3: a team member blocked by (or blocking) the buyer, or a shop whose
    # owner and buyer block each other: refused with the same codes as starting a chat.
    if (code = @conversation.team_block_code(current_user))
      message = code == :blocked ? "you have blocked this user" : "you have been blocked by this user"
      return render_unprocessable_entity(message, code: code)
    end

    # SHOP-2: a chat with a suspended/closed shop stays readable, but is shut
    # (Conversation#shut_by_shop?).
    if @conversation.shut_by_shop?
      return render_unprocessable_entity(I18n.t("shops.errors.not_open"), code: :shop_unavailable)
    end

    authorize @conversation, :send_message?

    # OFFLINE §10.1: a message the phone already got through (its answer was
    # lost) comes back as it is, never as a second message, even without an
    # Idempotency-Key.
    if (sent = already_sent_message)
      return render_blue(MessageSerializer, sent, view: :default, options: { current_user: current_user })
    end

    @message = @conversation.messages.new(safe_message_params)
    @message.user = current_user
    if @message.voice_message?
      return render_coded_error(VOICE_UNAVAILABLE, code: :voice_messages_unavailable, status: :service_unavailable) unless VoiceMessages.enabled?
      begin
        code = @message.assign_voice(params[:attachment])
      rescue VoiceMessages::Transcoder::Busy
        response.headers["Retry-After"] = VOICE_BUSY_RETRY_AFTER.to_s
        return render_coded_error(VOICE_BUSY, code: :voice_busy, status: :service_unavailable)
      end
      return render_unprocessable_entity(VOICE_REFUSALS.fetch(code), code: code) if code
    elsif params[:attachment].present?
      @message.attachment = params[:attachment]
    end

    if @message.save
      BroadcastMessageJob.perform_later(@message.id)   # in-app real-time (open app)
      SendMessagePushJob.perform_later(@message.id)     # push notification (closed app)
      render_blue(MessageSerializer, @message, view: :default, status: :created, options: { current_user: current_user })
    else
      # SF-B11: `code:` carries the ONE message failure the sender has to act on
      # — `offer_quantity_above_available_units`, when they offered for more units
      # than the listing has left. The `errors` array is unchanged English prose
      # (the fallback for clients that predate the code); the code is what lets a
      # ps/fa client pin its own localized sentence under the quantity stepper
      # instead of echoing a raw Rails string. Nil for every other validation
      # failure — a blank body, a rejected kind, a cross-conversation
      # `responds_to_id` — and `render_unprocessable_entity` omits the key then,
      # so those 422s are byte-identical to what they returned before.
      # Message#error_code owns the mapping, mirroring Listing#error_code.
      render_unprocessable_entity(@message, code: @message.error_code)
    end
  end

  def destroy
    authorize @message
    @message.soft_delete!
    BroadcastMessageJob.perform_later(@message.id) # real-time tombstone flip for the other participant
    render_blue(MessageSerializer, @message, view: :default, options: { current_user: current_user })
  end

  def mark_read
    authorize @conversation, :read_messages?
    @conversation.inbound_messages_for(current_user)
                 .where(read_at: nil)
                 .update_all(read_at: Time.current)
    head :no_content
  end

  private

  def set_conversation
    @conversation = policy_scope(Conversation).find(params[:conversation_id])
  end

  def already_sent_message
    return if params[:client_uuid].blank?

    @conversation.messages.find_by(user: current_user, client_uuid: params[:client_uuid].to_s)
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
  # SF-B11 adds `:offer_quantity` to the permit list. It is accepted on every
  # kind and then DISCARDED by the model wherever it cannot mean anything (a
  # non-offer kind, a single-item listing) rather than refused — see
  # `Message#discard_meaningless_offer_quantity`, which follows the rule
  # `Listing#units_for_sale` already set.
  def safe_message_params
    permitted = params.permit(:body, :responds_to_id, :offer_quantity, :client_uuid)
    raw_kind  = params[:kind].presence
    # Support: where the message was written from (Message#normalize_support_context).
    permitted[:context] = params[:context].permit(:mode, :shop_id).to_h if params[:context].respond_to?(:permit)

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
