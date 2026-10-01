# Bulk email to a filtered segment of users (docs/EMAIL.md). Email only.
#
# The audience is the SAME filter set as the users index (Admin::UserFilterSet),
# applied by the same code, so the segment listed there is the segment that
# receives. Nothing goes out in one step:
#
#   new      filters + four language versions, with per-language recipient
#            counts and what an empty box means, beside each box
#   preview  every filled version rendered; exclusions; quota; type-the-count
#   test     each filled version to the signed-in admin ([TEST])
#   create   only if the typed count equals a FRESHLY computed recipient count;
#            snapshots one AdminEmail per recipient, then AdminBulkEmailJob sends
#   show     live progress; Stop / Resume
module Admin
  class BulkEmailsController < Admin::ApplicationController
    include Admin::UserFilterSet

    before_action :load_draft, only: %i[new preview test create]
    before_action :set_bulk, only: %i[show stop resume]

    def new; end

    def preview
      return render(:new, status: :unprocessable_content) unless @bulk.valid?

      @rendered = @bulk.filled_locales.index_with { |loc| rendered_html(loc) }
    end

    def test
      return render(:new, status: :unprocessable_content) unless @bulk.valid?

      Admin::MailQuota.assert_dev_recipient_allowed!(current_admin_user.email)
      @bulk.filled_locales.each do |loc|
        AdminMessageMailer.bulk(draft_row(loc), to: current_admin_user.email).deliver_now
      end
      log_admin_action("bulk_email_test", details: @bulk.content.dig(@bulk.fallback_locale, "subject"))
      flash.now[:notice] = "Sent #{@bulk.filled_locales.size} test email(s) to #{current_admin_user.email}, one per language."
      preview_again
    rescue StandardError => e
      flash.now[:alert] = "Test not sent: #{e.message}"
      preview_again
    end

    def create
      return render(:new, status: :unprocessable_content) unless @bulk.valid?

      count = @audience.recipients_count
      if params[:confirm_count].to_i != count
        flash.now[:alert] = "Type the number of recipients (#{count}) to send. " \
                            "If you typed the number shown earlier, the segment has changed since — check it again."
        return preview_again
      end
      if count.zero?
        flash.now[:alert] = "Nobody in this segment can receive it."
        return preview_again
      end
      if count > Admin::MailQuota.remaining
        flash.now[:alert] = quota_refusal(count)
        return preview_again
      end
      recipients = @audience.recipients.to_a
      recipients.each { |u| Admin::MailQuota.assert_dev_recipient_allowed!(u.email) }

      snapshot!(recipients)
      AdminBulkEmailJob.perform_later(@bulk.id)
      log_admin_action("bulk_email", target: @bulk, details: "#{count} recipients · #{@bulk.segment}")
      redirect_to admin_bulk_email_path(@bulk), notice: "Sending to #{helpers.pluralize(count, 'person', plural: 'people')}."
    rescue Admin::MailQuota::DevRecipientNotAllowed => e
      flash.now[:alert] = "Refused, nothing sent: #{e.message}"
      preview_again
    end

    def show
      @rows = @bulk.admin_emails.includes(:user).order(:id).page(params[:page]).per(50)
      @counts = @bulk.counts
    end

    def stop
      @bulk.update!(status: :stopped)
      cancelled = @bulk.admin_emails.queued.update_all(status: AdminEmail.statuses[:cancelled])
      log_admin_action("bulk_email_stop", target: @bulk, details: "#{cancelled} not sent")
      redirect_to admin_bulk_email_path(@bulk), notice: "Stopped. #{cancelled} not sent."
    end

    def resume
      unless @bulk.remaining? && (@bulk.paused_daily_limit? || @bulk.sending?)
        return redirect_to admin_bulk_email_path(@bulk), alert: "Nothing left to send."
      end
      if Admin::MailQuota.remaining.zero?
        return redirect_to admin_bulk_email_path(@bulk), alert: quota_refusal(1)
      end

      @bulk.update!(status: :sending)
      AdminBulkEmailJob.perform_later(@bulk.id)
      log_admin_action("bulk_email_resume", target: @bulk)
      redirect_to admin_bulk_email_path(@bulk), notice: "Resumed."
    end

    private

    def load_draft
      @audience = Admin::BulkAudience.new(apply_admin_filters(User.all))
      raw = params.fetch(:content, {}).permit(AdminBulkEmail::LOCALES.index_with { %i[subject body] }).to_h
      @raw_content = raw
      @bulk = AdminBulkEmail.new(admin_user: current_admin_user,
                                 content: AdminBulkEmail.normalize_content(raw),
                                 fallback_locale: params[:fallback_locale].presence_in(AdminBulkEmail::LOCALES) || "en",
                                 segment: admin_filter_summary.presence || "All users",
                                 filter_params: admin_filter_values.compact)
    end

    def set_bulk
      @bulk = AdminBulkEmail.find(params[:id])
    end

    # One row per recipient, each with the version for their language — what
    # the admin approved is exactly what sends.
    def snapshot!(recipients)
      AdminBulkEmail.transaction do
        @bulk.recipients_count = recipients.size
        @bulk.save!
        recipients.each do |user|
          loc = @bulk.locale_for(user.preferred_language)
          @bulk.admin_emails.create!(user: user, admin_user: current_admin_user, locale: loc,
                                     subject: @bulk.content[loc]["subject"], body: @bulk.content[loc]["body"])
        end
      end
    end

    # A throwaway row for rendering: never saved, never sent to a real user.
    def draft_row(loc)
      AdminEmail.new(admin_bulk_email: @bulk, locale: loc, user: User.new(preferred_language: loc),
                     subject: @bulk.content[loc]["subject"], body: @bulk.content[loc]["body"])
    end

    def rendered_html(loc)
      html = AdminMessageMailer.bulk(draft_row(loc), to: "preview@invalid").html_part&.body&.decoded
      html && String.new(html) # plain String: escaped into srcdoc like any value
    end

    def quota_refusal(count)
      room = Admin::MailQuota.room_at
      "Over the daily limit: #{count} would go out, but only #{Admin::MailQuota.remaining} of " \
        "#{Admin::MailQuota::DAILY_LIMIT} are left in the last 24 hours" \
        "#{room ? "; more room from #{I18n.l(room, format: :short)}" : ''}."
    end

    def preview_again
      @rendered = @bulk.valid? ? @bulk.filled_locales.index_with { |loc| rendered_html(loc) } : {}
      render :preview
    end
  end
end
