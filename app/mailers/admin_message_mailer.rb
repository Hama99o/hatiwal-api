# An email an admin wrote to one user (AdminEmail). Sent from — and replying
# to — the Hatiwal mail account (ApplicationMailer / docs/EMAIL.md).
class AdminMessageMailer < ApplicationMailer
  # The templates are complete documents, like UserMailer's.
  layout false

  # to: overrides the recipient for "send a test to me": the admin receives
  # exactly what the user would, with [TEST] in the subject.
  def direct(admin_email, to: nil)
    @admin_email = admin_email
    @user = admin_email.user
    subject = to ? "[TEST] #{admin_email.subject}" : admin_email.subject

    mail(to: to || @user.email, subject: subject)
  end
end
