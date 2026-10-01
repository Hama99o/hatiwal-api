require "rails_helper"

RSpec.describe AdminEmailDeliveryJob, type: :job do
  let(:email) { create(:admin_email) }

  before { ActionMailer::Base.deliveries.clear }

  it "sends it to the user, from and replying to the Hatiwal mail account, and marks it sent" do
    described_class.perform_now(email.id)

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ email.user.email ])
    expect(mail.from).to eq([ Rails.application.config.x.mail_sender ])
    expect(mail.reply_to).to eq([ Rails.application.config.x.mail_sender ])
    expect(mail.subject).to eq(email.subject)
    expect(mail.html_part.body.decoded).to include('dir="auto"').and include(email.body)
    expect(email.reload).to be_sent
    expect(email.sent_at).to be_present
  end

  it "records a failure instead of raising, so it shows in the history" do
    allow(AdminMessageMailer).to receive(:direct).and_raise(Net::SMTPAuthenticationError, "535 bad credentials")

    expect { described_class.perform_now(email.id) }.not_to raise_error
    expect(email.reload).to be_failed
    expect(email.error).to include("535 bad credentials")
  end

  # Regression: with raise_delivery_errors off (development.rb), an SMTP
  # rejection was swallowed and the email recorded as sent.
  it "records a failure even where the environment swallows delivery errors" do
    allow(ActionMailer::Base).to receive(:raise_delivery_errors).and_return(false)
    allow_any_instance_of(Mail::TestMailer).to receive(:deliver!)
      .and_raise(Net::SMTPAuthenticationError, "535 Username and Password not accepted")

    described_class.perform_now(email.id)

    expect(email.reload).to be_failed
    expect(email.error).to include("535")
  end

  # Email can't be unsent: a second run must not mail the user again.
  it "never sends twice" do
    described_class.perform_now(email.id)
    described_class.perform_now(email.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
