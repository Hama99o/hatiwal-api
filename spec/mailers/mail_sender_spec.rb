require "rails_helper"

# Every email is FROM the account that sends it and replies come back to it.
# hatiwal.com authorises no sender and has no MX, so a hatiwal.com From or
# Reply-To would be rejected or bounce (config.x.mail_sender).
RSpec.describe "Mail sender" do
  let(:sender) { Rails.application.config.x.mail_sender }
  let(:user)   { create(:user) }

  it "is the SMTP account" do
    expect(sender).to eq(Rails.application.credentials[:smtp_username].presence || "noreply@hatiwal.com")
  end

  it "sends app emails from, and with replies to, that account" do
    mail = UserMailer.reset_password(user, "raw-token")

    expect(mail.from).to eq([ sender ])
    expect(mail.reply_to).to eq([ sender ])
  end

  it "sends Devise account emails (confirmation) from the same account" do
    mail = Devise::Mailer.confirmation_instructions(user, "token")

    expect(mail.from).to eq([ sender ])
  end
end
