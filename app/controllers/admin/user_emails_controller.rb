# "Email this user" from the admin user page (docs/EMAIL.md).
#
# Email can't be unsent, so nothing goes out in one click:
#   new      → write subject + body
#   preview  → the real rendered email, still editable, with two actions:
#   test     → send it to the signed-in admin ([TEST] subject), stay on preview
#   create   → only from the preview's Send button (send=1) plus a confirm
#              dialog; records an AdminEmail and delivers it in the background
module Admin
  class UserEmailsController < Admin::ApplicationController
    before_action :set_user

    def new
      @admin_email = draft
    end

    def preview
      @admin_email = draft
      return render(:new, status: :unprocessable_content) unless @admin_email.valid?

      @rendered = rendered_html(@admin_email)
    end

    def test
      @admin_email = draft
      return render(:new, status: :unprocessable_content) unless @admin_email.valid?

      AdminMessageMailer.direct(@admin_email, to: current_admin_user.email).deliver_now
      log_admin_action("email_user_test", target: @user, details: @admin_email.subject)
      flash.now[:notice] = "Test sent to #{current_admin_user.email}. Check it, then send to the user."
      preview_again
    rescue StandardError => e
      flash.now[:alert] = "Test not sent: #{e.message}"
      preview_again
    end

    def create
      @admin_email = draft
      unless params[:send] == "1"
        flash.now[:alert] = "Preview the email and use its Send button."
        return preview_again
      end
      return render(:new, status: :unprocessable_content) unless @admin_email.save

      @admin_email.deliver_later!
      log_admin_action("email_user", target: @user, details: @admin_email.subject)
      redirect_to admin_user_path(@user, anchor: "user-email"), notice: "Email to #{@user.email} queued."
    end

    private

    def set_user
      @user = User.find(params[:user_id])
    end

    def draft
      AdminEmail.new(user: @user, admin_user: current_admin_user,
                     subject: params[:subject].to_s.strip, body: params[:body].to_s.strip)
    end

    # The email's HTML as a PLAIN String. Mail hands back an html_safe
    # SafeBuffer, which ERB then won't escape: inside srcdoc="…" its first quote
    # closed the attribute and the rest of the email spilled into the admin page
    # (breaking the form under it). A plain String is escaped like any value.
    def rendered_html(admin_email)
      html = AdminMessageMailer.direct(admin_email).html_part&.body&.decoded
      html && String.new(html)
    end

    def preview_again
      @rendered = rendered_html(@admin_email) if @admin_email.valid?
      render :preview
    end
  end
end
