# Support inbox: every user ⇄ Hatiwal Support thread, and a reply box.
#
# Hand-built like DashboardController rather than an Administrate dashboard:
# a support thread is a Conversation scoped to kind :support, and the screen
# is a chat, not a CRUD table.
#
# Replies are posted AS the Support account, with Message#admin_user recording
# which admin wrote them, and go out through the same broadcast + push jobs as
# any chat message.
#
# STARTING a thread is the one dangerous action, and it is OFF by default. See
# docs/SUPPORT_MESSAGING.md: a user-opened thread is safe by construction (only
# the new app can open one), but an admin-opened one would reach users still on
# v1.0.4, which renders it as a removed-listing chat.
module Admin
  class SupportConversationsController < Admin::ApplicationController
    PER_PAGE = 25

    before_action :set_conversation, only: %i[show reply close reopen]
    helper_method :admin_initiate_enabled?

    # Read per call (not memoized) so flipping the env var and restarting is
    # the whole switch. Off unless explicitly "true".
    def self.admin_initiate_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("SUPPORT_ADMIN_INITIATE", "false"))
    end

    def index
      threads = Conversation.kind_support
      @total = threads.count
      # Waiting on us first, then most recent activity. In SQL, not Ruby, so the
      # order holds across pages rather than only within one.
      @conversations = threads.order(awaiting_reply_first).ordered.includes(:buyer, :latest_message)
                              .page(params[:page]).per(PER_PAGE)
      @unread_counts = unread_counts_for(@conversations.map(&:id))
    end

    def show
      # Opening the thread is reading it: the user's messages are now read by
      # Support (the same read_at the app shows as read receipts).
      @conversation.messages.where(read_at: nil, user_id: @conversation.buyer_id)
                   .update_all(read_at: Time.current)
      @messages = @conversation.messages.includes(:admin_user, attachment_attachment: :blob)
                               .order(:created_at)
    end

    def reply
      if @conversation.closed?
        return redirect_to admin_support_conversation_path(@conversation),
                           alert: "This conversation is closed. Reopen it to reply."
      end

      message = @conversation.messages.new(
        user: @conversation.seller, admin_user: current_admin_user,
        kind: :text, body: params[:body].to_s.strip
      )
      if message.save
        BroadcastMessageJob.perform_later(message.id)
        SendMessagePushJob.perform_later(message.id)
        log_admin_action("support_reply", target: @conversation)
        redirect_to admin_support_conversation_path(@conversation), notice: "Reply sent."
      else
        redirect_to admin_support_conversation_path(@conversation),
                    alert: "Reply not sent: #{message.errors.full_messages.to_sentence}"
      end
    end

    def close
      @conversation.closed!
      log_admin_action("support_close", target: @conversation)
      redirect_to admin_support_conversation_path(@conversation), notice: "Conversation closed."
    end

    def reopen
      @conversation.open!
      log_admin_action("support_reopen", target: @conversation)
      redirect_to admin_support_conversation_path(@conversation), notice: "Conversation reopened."
    end

    # Admin-initiated: open (or go to) a user's support thread from their page.
    # An EXISTING thread is always reachable; creating one needs the flag.
    def create
      user = User.find(params[:user_id])
      existing = Conversation.kind_support.find_by(buyer_id: user.id)
      return redirect_to admin_support_conversation_path(existing) if existing

      unless self.class.admin_initiate_enabled?
        return redirect_to admin_user_path(user),
                           alert: "Starting a support conversation is turned off until the app " \
                                  "update with support messaging is live (SUPPORT_ADMIN_INITIATE)."
      end

      conversation = Conversation.support_thread_for!(user)
      log_admin_action("support_start", target: conversation)
      redirect_to admin_support_conversation_path(conversation)
    end

    private

    def admin_initiate_enabled? = self.class.admin_initiate_enabled?

    def set_conversation
      @conversation = Conversation.kind_support.includes(:buyer).find(params[:id])
    end

    # Messages the USER sent that Support hasn't read. On a support thread the
    # user is always the buyer, so "unread from the user" is buyer_id-authored.
    def unread_from_user
      Message.where(read_at: nil).where("messages.user_id = conversations.buyer_id")
             .where("messages.conversation_id = conversations.id")
    end

    def awaiting_reply_first
      Arel::Nodes::Case.new.when(unread_from_user.arel.exists).then(0).else(1)
    end

    # One GROUP BY for the page.
    def unread_counts_for(ids)
      Message.joins(:conversation).where(conversation_id: ids, read_at: nil)
             .where("messages.user_id = conversations.buyer_id")
             .group(:conversation_id).count
    end
  end
end
