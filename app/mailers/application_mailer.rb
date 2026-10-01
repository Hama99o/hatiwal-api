class ApplicationMailer < ActionMailer::Base
  # From the account that actually sends, and replies back to it — the only
  # inbox in play that can receive mail (config.x.mail_sender explains why).
  default from: Rails.application.config.x.mail_sender,
          reply_to: Rails.application.config.x.mail_sender
  layout "mailer"
end
