# Prohibited items (owner, 2026-10-13): "a new flag is waiting" to one admin
# account, sent by Flag#email_admins when FLAG_EMAILS_ENABLED. English: the
# admin is English.
class AdminFlagMailer < ApplicationMailer
  layout false

  def new_flag(flag, admin_user)
    @flag = flag
    @admin_user = admin_user
    @url = admin_flag_url(flag)
    what = flag.listing? ? "Listing" : "Shop"
    why = flag.category ? flag.category.humanize : "prohibited item report"

    mail(to: admin_user.email, subject: "[Hatiwal] Flagged #{what.downcase}: #{flag.flaggable_label.to_s.truncate(60)} (#{why})")
  end
end
