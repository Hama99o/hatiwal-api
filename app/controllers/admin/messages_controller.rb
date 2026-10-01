# Messages: pick a person, pick how to reach them (email, in-app as Hatiwal
# Support, or both), write once, send — and one history of everything sent.
#
#   index    → the history (AdminOutreach), newest first
#   new      → find the recipient (?q=), then compose (?user_id=)
#   preview  → what will go out on each chosen channel; still editable
#   test     → the EMAIL to the signed-in admin ([TEST] subject); in-app has no test
#   create   → only from the preview's Send button (send=1) + a confirm dialog
#
# Nothing here decides what is allowed: Admin::SendMessage validates every
# channel, and the in-app gate is Conversation.admin_can_message?.
module Admin
  class MessagesController < Admin::ApplicationController
    SEARCH_LIMIT = 10

    before_action :set_recipient, only: %i[new preview test create]

    # One history: one-to-one sends and bulk emails, newest first.
    HISTORY_LIMIT = 100

    def index
      outreaches = AdminOutreach.includes(:user, :admin_user, :admin_email, :message).recent.limit(HISTORY_LIMIT)
      bulks = AdminBulkEmail.includes(:admin_user).recent.limit(HISTORY_LIMIT)
      @entries = (outreaches.to_a + bulks.to_a).sort_by(&:created_at).reverse.first(HISTORY_LIMIT)
      @bulk_counts = AdminEmail.where(admin_bulk_email_id: bulks.map(&:id)).group(:admin_bulk_email_id, :status).count
    end

    def new
      @results = search(params[:q]) if @user.nil? && params[:q].present?
      @sender = build_sender if @user
    end

    def preview
      @sender = build_sender
      return render(:new, status: :unprocessable_content) unless @sender.valid?

      @rendered = rendered_email_html if @sender.email?
    end

    def test
      @sender = build_sender
      return render(:new, status: :unprocessable_content) unless @sender.valid?

      if @sender.email?
        AdminMessageMailer.direct(draft_email, to: current_admin_user.email).deliver_now
        log_admin_action("message_test", target: @user, details: @sender.subject)
        flash.now[:notice] = "Test email sent to #{current_admin_user.email}. In-app messages have no test."
      else
        flash.now[:alert] = "Only the email can be tested. There is no admin app to receive an in-app test."
      end
      preview_again
    rescue StandardError => e
      flash.now[:alert] = "Test not sent: #{e.message}"
      preview_again
    end

    def create
      @sender = build_sender
      unless params[:send] == "1"
        flash.now[:alert] = "Preview the message and use its Send button."
        return preview_again
      end
      return render(:new, status: :unprocessable_content) unless @sender.call

      log_admin_action("message_user", target: @user, details: @sender.outreach.channels.join(" + "))
      redirect_to admin_messages_path, notice: "Sent to #{@user.full_name} by #{@sender.outreach.channels.join(' + ')}."
    end

    private

    def set_recipient
      raw = params.fetch(:content, {}).permit(Admin::LanguageVersions::LOCALES.index_with { %i[subject body] }).to_h
      @raw_content = raw
      @fallback_locale = params[:fallback_locale].presence_in(Admin::LanguageVersions::LOCALES) || "en"
      @user = User.members.find_by(id: params[:user_id]) if params[:user_id].present?
      return unless @user

      # What each channel can't do for this user — shown greyed with the reason.
      @email_refusal = @user.email_refusal_reason
      @in_app_refusal = Conversation.admin_message_refusal(@user)
    end

    # Name, email or phone. Members only (never the Support account).
    def search(term)
      like = "%#{ActiveRecord::Base.sanitize_sql_like(term.to_s.strip)}%"
      User.members.where("firstname ILIKE :q OR lastname ILIKE :q OR email ILIKE :q OR phone ILIKE :q " \
                         "OR (firstname || ' ' || lastname) ILIKE :q", q: like)
          .order(:firstname).limit(SEARCH_LIMIT)
    end

    def build_sender
      Admin::SendMessage.new(admin: current_admin_user, user: @user, channels: params[:channels],
                             content: @raw_content, fallback_locale: @fallback_locale,
                             opt_out_acknowledged: params[:opt_out_acknowledged])
    end

    # The version THIS user gets, as an unsaved email for preview/test.
    def draft_email
      AdminEmail.new(user: @user, admin_user: current_admin_user, locale: @sender.locale,
                     subject: @sender.subject, body: @sender.body)
    end

    # A plain String: Mail hands back an html_safe SafeBuffer, which ERB would
    # not escape inside srcdoc="…" (it once spilled the email into the page).
    def rendered_email_html
      html = AdminMessageMailer.direct(draft_email).html_part&.body&.decoded
      html && String.new(html)
    end

    def preview_again
      @rendered = rendered_email_html if @sender.email? && @sender.valid?
      render :preview
    end
  end
end
