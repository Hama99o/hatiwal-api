require "rails_helper"

# In-app bulk: a broadcast into Support threads. There is no unsubscribe for a
# Support thread, so the restraints are: the per-recipient gate, archive-as-
# mute, push off unless chosen, one broadcast per person per 7 days, plain
# text, and a confirm that says it plainly.
RSpec.describe "Admin bulk message — in-app", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let!(:with_thread)    { create(:user, city: "Kabul", preferred_language: "ps", push_token: "ExponentPushToken[a]") }
  let!(:also_thread)    { create(:user, city: "Kabul", preferred_language: "en") }
  let!(:without_thread) { create(:user, city: "Kabul", preferred_language: "fa") }
  let(:content) { { "en" => { "body" => "Hello Kabul" }, "ps" => { "body" => "سلام کابل" } } }
  let(:draft)   { { city: "Kabul", channels: %w[in_app], fallback_locale: "en", content: content } }

  before do
    # Pushes really fire now (owner: always with a notification); never hit Expo.
    allow(Notifications::ExpoPushService).to receive(:deliver)
      .and_return(Notifications::ExpoPushService::Result.new(ok: true, error: nil, details: nil))
    sign_in admin, scope: :admin_user
    Conversation.support_thread_for!(with_thread) # user-opened = on the new app
    Conversation.support_thread_for!(also_thread)
  end

  def flag(on)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return(on ? "true" : "false")
  end

  def send_it(params = draft, count: 2)
    perform_enqueued_jobs { post admin_bulk_emails_path, params: params.merge(confirm_count: count) }
  end

  it "shows, before sending, who can and can't receive in-app, and who can't get a push" do
    get new_admin_bulk_email_path(city: "Kabul")

    expect(response.body[%r{<span id="in-app-reach">.*?</span>}m]).to include("2 can receive in-app · 1 can't")
    expect(response.body[%r{<div class="ad-note" id="in-app-push-reach">.*?</div>}m]).to include("1 of 2 can't receive a push")
  end

  it "the gate is per recipient: sends to those with a thread, never creates one for the rest" do
    send_it

    bulk = AdminBulkEmail.last
    expect(bulk.in_app_deliveries.pluck(:user_id)).to contain_exactly(with_thread.id, also_thread.id)
    expect(Conversation.kind_support.where(buyer_id: without_thread.id)).not_to exist
    expect(Conversation.kind_support.find_by(buyer_id: with_thread.id).messages.last.body).to eq("سلام کابل")
    expect(Conversation.kind_support.find_by(buyer_id: also_thread.id).messages.last.body).to eq("Hello Kabul")
  end

  it "needs no subject for in-app only" do
    send_it
    expect(AdminBulkEmail.last).to be_finished
  end

  it "re-checks the gate at SEND time and records a refusal instead of creating a thread" do
    flag(true)
    post admin_bulk_emails_path, params: draft.merge(confirm_count: 3) # all 3 pass while the flag is on
    flag(false)                                                         # ...then it's turned off

    perform_enqueued_jobs

    skipped = AdminBulkEmail.last.in_app_deliveries.find_by(user: without_thread)
    expect(skipped).to be_skipped
    expect(skipped.error).to include("not allowed at send time")
    expect(Conversation.kind_support.where(buyer_id: without_thread.id)).not_to exist
  end

  # Owner: a message always goes with a push; whoever can't receive one
  # simply doesn't get it.
  it "always pushes everyone who can receive one, and notes who can't" do
    send_it

    notes = AdminBulkInAppDelivery.all.to_h { |d| [ d.user_id, d.push_note ] }
    expect(notes[with_thread.id]).to eq("push sent")
    expect(notes[also_thread.id]).to start_with("no push token")
  end

  # Archive-as-mute: a broadcast respects the archive, a personal reply doesn't.
  it "delivers quietly to someone who archived Support: stays archived, no push" do
    thread = Conversation.kind_support.find_by(buyer_id: with_thread.id)
    thread.archive_for!(with_thread)

    send_it

    expect(thread.reload.archived_for?(with_thread)).to be(true)
    expect(AdminBulkInAppDelivery.find_by(user: with_thread).push_note).to eq("no push: archived Support")
  end

  it "a personal reply still brings an archived thread back" do
    thread = Conversation.kind_support.find_by(buyer_id: with_thread.id)
    thread.archive_for!(with_thread)

    post reply_admin_support_conversation_path(thread), params: { body: "Answer to your question" }

    expect(thread.reload.archived_for?(with_thread)).to be(false)
  end

  it "one broadcast per person per 7 days: recent recipients are excluded and counted" do
    send_it

    get new_admin_bulk_email_path(city: "Kabul")
    expect(response.body).to include("2 got a broadcast in the last 7 days, excluded")
    expect(response.body[%r{<span id="in-app-reach">.*?</span>}m]).to include("0 can receive in-app")
  end

  it "the confirm says plainly they can't unsubscribe" do
    post preview_admin_bulk_emails_path, params: draft

    expect(CGI.unescapeHTML(response.body[%r{<label for="confirm-count" id="confirm-text">.*?</label>}m]))
      .to include("2 users' Support conversations").and include("They can't unsubscribe from it — only archive Support")
  end

  it "keeps in-app text to a chat message's length" do
    long = { "en" => { "body" => "x" * (Message::BODY_MAX + 1) } }
    post preview_admin_bulk_emails_path, params: draft.merge(content: long)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("In-app messages are at most #{Message::BODY_MAX} characters")
  end

  it "Stop cancels queued in-app deliveries too" do
    post admin_bulk_emails_path, params: draft.merge(confirm_count: 2)
    bulk = AdminBulkEmail.last

    patch stop_admin_bulk_email_path(bulk)
    perform_enqueued_jobs

    expect(bulk.in_app_deliveries.cancelled.count).to eq(2)
    expect(Message.where(body: [ "Hello Kabul", "سلام کابل" ])).to be_empty
  end

  it "development refuses a broadcast push to devices holding a token" do
    allow(Rails.env).to receive(:development?).and_return(true)

    post admin_bulk_emails_path, params: draft.merge(confirm_count: 2)

    expect(AdminBulkEmail.count).to eq(0)
    expect(CGI.unescapeHTML(response.body)).to include("won't send a broadcast push")
  end

  it "email + in-app: the confirm number counts each person once" do
    [ with_thread, also_thread, without_thread ].each { |u| u.update!(confirmed_at: Time.current) }

    post preview_admin_bulk_emails_path,
         params: draft.merge(channels: %w[email in_app], content: { "en" => { "subject" => "Hi", "body" => "Hello" } })

    expect(response.body).to include('data-expected="3"')
  end

  describe "Send bulk mail / Send bulk message" do
    it "Send bulk message: four language boxes, NO subjects, push option" do
      get new_admin_bulk_email_path(city: "Kabul", mode: "in_app")

      expect(response.body).to include(">Send bulk message</h1>").and include("A push notification goes with it")
      expect(response.body.scan('class="bulk-lang').size).to eq(4)
      expect(response.body).not_to include("content[en][subject]")
    end

    it "Send bulk mail: four language boxes WITH subjects, no push option" do
      get new_admin_bulk_email_path(city: "Kabul", mode: "email")

      expect(response.body).to include(">Send bulk mail</h1>").and include("content[en][subject]")
      expect(response.body).not_to include("A push notification goes with it")
    end

    it "the Users list offers both, carrying its filters" do
      get admin_users_path(city: "Kabul")

      expect(response.body).to include("mode=email").and include("mode=in_app").and include('id="message-these-users"')
    end
  end
end
