# Support inbox: every Hatiwal Support thread, a person's or (owner,
# 2026-10-12) a shop's, and a reply box.
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
    # How often the inbox and an open thread poll for new messages (by reload).
    REFRESH_SECONDS = 30

    before_action :set_conversation, only: %i[show reply close reopen]
    helper_method :admin_initiate_enabled?

    # The gate lives on Conversation; kept here as a delegate for the views.
    def self.admin_initiate_enabled? = Conversation.admin_initiate_enabled?

    def index
      threads = Conversation.kind_support
      @total = threads.count
      # Waiting on us first, then most recent activity. In SQL, not Ruby, so the
      # order holds across pages rather than only within one.
      @conversations = threads.order(awaiting_reply_first).ordered.includes(:buyer, :latest_message, shop: :owner)
                              .page(params[:page]).per(PER_PAGE)
      @unread_counts = unread_counts_for(@conversations.map(&:id))
    end

    def show
      # Opening the thread is reading it: the user's messages are now read by
      # Support (the same read_at the app shows as read receipts).
      @conversation.messages.where(read_at: nil).where(Conversation::NOT_FROM_SUPPORT_SQL)
                   .update_all(read_at: Time.current)
      @messages = @conversation.messages.includes(:admin_user, :user, attachment_attachment: :blob)
                               .order(:created_at)
    end

    # Through Admin::SendMessage like every admin send, so thread replies land
    # in the same Messages history (source: support_inbox).
    def reply
      return reply_to_shop if @conversation.shop_support?

      sender = Admin::SendMessage.reply(admin: current_admin_user, user: @conversation.buyer, body: params[:body])
      if sender.call
        log_admin_action("support_reply", target: @conversation)
        redirect_to admin_support_conversation_path(@conversation), notice: "Reply sent."
      else
        redirect_to admin_support_conversation_path(@conversation),
                    alert: "Reply not sent: #{sender.errors.to_sentence}"
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

    private

    def admin_initiate_enabled? = self.class.admin_initiate_enabled?

    # A shop's own thread (owner, 2026-10-12): the reply goes to the whole team,
    # written by the Support account and signed by the admin, with the usual
    # broadcast + push. Admin::SendMessage is one person's history (AdminOutreach),
    # so a shop's reply is audited here instead.
    def reply_to_shop
      body = params[:body].to_s.strip
      message = @conversation.messages.new(user: @conversation.support_user, admin_user: current_admin_user, kind: :text, body: body)
      if @conversation.open? && message.save
        BroadcastMessageJob.perform_later(message.id)
        SendMessagePushJob.perform_later(message.id)
        log_admin_action("support_reply", target: @conversation)
        redirect_to admin_support_conversation_path(@conversation), notice: "Reply sent to the shop's team."
      else
        reason = @conversation.open? ? message.errors.full_messages.to_sentence : "the conversation is closed"
        redirect_to admin_support_conversation_path(@conversation), alert: "Reply not sent: #{reason}"
      end
    end

    def set_conversation
      @conversation = Conversation.kind_support.includes(:buyer, shop: :owner).find(params[:id])
    end

    # Same condition as Conversation.awaiting_support_reply (one definition, not
    # two), as a sort key: the subquery is uncorrelated, so it reads cleanly.
    def awaiting_reply_first
      Arel.sql("CASE WHEN conversations.id IN (#{Conversation.awaiting_support_reply.select(:id).to_sql}) THEN 0 ELSE 1 END")
    end

    # One GROUP BY for the page.
    def unread_counts_for(ids)
      Message.joins(:conversation).where(conversation_id: ids, read_at: nil)
             .where(Conversation::NOT_FROM_SUPPORT_SQL)
             .group(:conversation_id).count
    end
  end
end
