require "rails_helper"

RSpec.describe Admin::SendMessage do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:user)  { create(:user, push_token: "ExponentPushToken[u]") }

  def sender(**opts)
    described_class.new(admin: admin, user: user, body: "سلام، ستاسو حساب تایید شو.", subject: "Your account", **opts)
  end

  def flag(on)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return(on ? "true" : "false")
  end

  it "sends an email: one outreach, one AdminEmail, delivery queued" do
    s = sender(channels: %w[email])

    expect { expect(s.call).to be(true) }.to have_enqueued_job(AdminEmailDeliveryJob)
    expect(s.outreach).to have_attributes(via_email: true, via_in_app: false, source: "compose")
    expect(s.outreach.admin_email).to have_attributes(user: user, subject: "Your account")
  end

  it "sends in-app to a user who opened support (flag off): Support message + push queued" do
    flag(false)
    thread = Conversation.support_thread_for!(user)

    s = sender(channels: %w[in_app])
    expect { s.call }.to have_enqueued_job(SendMessagePushJob)

    expect(s.outreach.message).to have_attributes(conversation_id: thread.id, user_id: User.support_account!.id,
                                                  admin_user_id: admin.id)
    expect(s.outreach.push_note).to eq("push queued")
  end

  # The gate, server-side: a tampered form must not reach a v1.0.4 user.
  it "refuses in-app for a user with no thread while the flag is off, and sends NOTHING on any channel" do
    flag(false)
    s = sender(channels: %w[email in_app])

    expect(s.call).to be(false)
    expect(s.errors.join).to include("SUPPORT_ADMIN_INITIATE")
    expect(Conversation.kind_support.count).to eq(0)
    expect(AdminEmail.count).to eq(0)
    expect(AdminOutreach.count).to eq(0)
  end

  it "sends both, as ONE outreach, once the gate allows" do
    flag(true)
    s = sender(channels: %w[email in_app])

    expect(s.call).to be(true)
    expect(AdminOutreach.count).to eq(1)
    expect(s.outreach.channels).to eq(%w[Email In-app])
  end

  it "notes, at send time, when no push can be delivered — with the app's own reason" do
    flag(true)
    user.update!(push_token: nil, push_registration_error: "token: Default FirebaseApp is not initialized")

    s = sender(channels: %w[in_app])
    s.call

    expect(s.outreach.push_note).to eq("no push token: token: Default FirebaseApp is not initialized")
  end

  it "requires acknowledgement to email someone who unsubscribed from bulk, and records it" do
    user.update!(email_opt_out_at: 1.day.ago)

    expect(sender(channels: %w[email]).call).to be(false)

    s = sender(channels: %w[email], opt_out_acknowledged: "1")
    expect(s.call).to be(true)
    expect(s.outreach.opt_out_acknowledged).to be(true)
  end

  it "refuses an email without a subject, and an unknown channel does nothing" do
    expect(described_class.new(admin: admin, user: user, body: "x", channels: %w[email]).valid?).to be(false)
    expect(sender(channels: %w[sms]).valid?).to be(false)
  end
end
