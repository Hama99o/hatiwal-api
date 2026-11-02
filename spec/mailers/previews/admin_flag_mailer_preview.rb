# Preview at /rails/mailers/admin_flag_mailer/new_flag (development). Uses the
# newest flag and admin in the database; an unsaved example when there is none.
class AdminFlagMailerPreview < ActionMailer::Preview
  def new_flag
    admin = AdminUser.first || AdminUser.new(name: "Admin", email: "admin@hatiwal.com")
    flag = Flag.order(:id).last || example_flag
    AdminFlagMailer.new_flag(flag, admin)
  end

  private

  def example_flag
    listing = Listing.new(id: 0, title: "Hunting rifle, almost new")
    Flag.new(id: 0, flaggable: listing, source: :term, category: :firearms, matched_term: "rifle")
  end
end
