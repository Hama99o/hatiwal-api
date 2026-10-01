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

  # One recipient of a bulk send. Same template, plus a one-click unsubscribe:
  # a link in the footer and the List-Unsubscribe / List-Unsubscribe-Post
  # headers (RFC 8058) that Gmail and Yahoo require of bulk senders.
  def bulk(admin_email, to: nil)
    @admin_email = admin_email
    @user = admin_email.user
    # A test or preview copy must never carry a WORKING unsubscribe for a real
    # person (an admin clicking it would opt them out): it gets a dummy token,
    # which the page answers with "this link isn't valid".
    token = to ? "test-copy" : @user.signed_id(purpose: User::UNSUBSCRIBE_PURPOSE)
    @unsubscribe_url = unsubscribe_url(token: token)
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    subject = to ? "[TEST] #{admin_email.subject}" : admin_email.subject

    mail(to: to || @user.email, subject: subject, template_name: "direct")
  end
end
