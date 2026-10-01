require "rails_helper"

RSpec.describe AdminBulkEmailJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:bulk) do
    AdminBulkEmail.create!(admin_user: admin, content: { "en" => { "subject" => "Hi", "body" => "Hello" } },
                           fallback_locale: "en", segment: "All users")
  end

  def rows(n)
    Array.new(n) do
      bulk.admin_emails.create!(user: create(:user, confirmed_at: Time.current), admin_user: admin,
                                locale: "en", subject: "Hi", body: "Hello")
    end
  end

  before { ActionMailer::Base.deliveries.clear }

  it "sends one batch, then re-enqueues itself for the rest (the rate limit)" do
    rows(AdminBulkEmailJob::BATCH + 3)

    expect { described_class.perform_now(bulk.id) }.to have_enqueued_job(described_class).with(bulk.id)
    expect(ActionMailer::Base.deliveries.size).to eq(AdminBulkEmailJob::BATCH)

    described_class.perform_now(bulk.id)
    expect(ActionMailer::Base.deliveries.size).to eq(AdminBulkEmailJob::BATCH + 3)
    expect(bulk.reload).to be_finished
  end

  it "every bulk email carries one-click unsubscribe" do
    rows(1)
    described_class.perform_now(bulk.id)

    mail = ActionMailer::Base.deliveries.last
    expect(mail["List-Unsubscribe"].value).to match(%r{<http.*/unsubscribe/.+>})
    expect(mail["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    expect(mail.html_part.body.decoded).to include("/unsubscribe/")
  end

  # Email can't be unsent: a duplicated or retried run must not mail twice.
  it "never sends a row twice, even if the job runs twice" do
    rows(3)
    2.times { described_class.perform_now(bulk.id) }

    expect(ActionMailer::Base.deliveries.size).to eq(3)
  end

  it "stops sending once the campaign is stopped" do
    rows(3)
    bulk.update!(status: :stopped)

    described_class.perform_now(bulk.id)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "pauses at the daily limit instead of letting the sender reject mid-run" do
    rows(2)
    allow(Admin::MailQuota).to receive(:remaining).and_return(1, 0)

    described_class.perform_now(bulk.id)

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(bulk.reload).to be_paused_daily_limit
    expect(bulk.admin_emails.queued.count).to eq(1)
  end

  # A worker that died mid-SMTP: the row may have gone out, so never resend it.
  it "marks a long-stuck 'sending' row failed as interrupted, and does not resend it" do
    stuck = rows(1).first
    stuck.update_columns(status: AdminEmail.statuses[:sending], updated_at: 1.hour.ago)

    described_class.perform_now(bulk.id)

    expect(stuck.reload).to be_failed
    expect(stuck.error).to include("interrupted")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "development may only email the mail account itself — anything else fails loudly, not silently" do
    row = rows(1).first
    allow(Rails.env).to receive(:development?).and_return(true)

    described_class.perform_now(bulk.id)

    expect(row.reload).to be_failed
    expect(row.error).to include("DevRecipientNotAllowed")
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
