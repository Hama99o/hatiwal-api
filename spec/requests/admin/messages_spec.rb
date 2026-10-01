require "rails_helper"

RSpec.describe "Admin Messages", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user)  { create(:user, firstname: "Zarmina", lastname: "Khan", email: "zarmina@example.com", phone: "0700123456") }
  let(:draft) { { user_id: user.id, channels: %w[email], subject: "About your listing", body: "سلام — ستاسو اعلان تایید شو." } }

  before do
    sign_in admin, scope: :admin_user
    ActionMailer::Base.deliveries.clear
  end

  it "is in the navigation" do
    get admin_root_path
    expect(response.body).to include('id="nav-messages"')
  end

  it "finds a recipient by name, email or phone — never the Support account" do
    user
    User.support_account!

    %w[Zarmina zarmina@ 0700123].each do |q|
      get new_admin_message_path(q: q)
      expect(response.body[%r{<ul id="recipient-results".*?</ul>}m]).to include("Zarmina Khan")
    end
    get new_admin_message_path(q: "Support")
    expect(response.body).not_to include('id="recipient-results"')
  end

  it "always shows the in-app channel, greyed with the reason, while the gate is closed" do
    get new_admin_message_path(user_id: user.id)

    channel = response.body[%r{<label class="channel" data-channel="in_app".*?</label>}m]
    expect(channel).to include("disabled").and include("needs the app update with support messaging")
  end

  it "warns at compose time when the user can't receive push" do
    user.update!(push_token: nil, push_registration_error: "token: Default FirebaseApp is not initialized")

    get new_admin_message_path(user_id: user.id)

    expect(response.body).to include('id="no-push-warning"').and include("Default FirebaseApp")
  end

  it "previews without sending or recording, escaping the email into the iframe" do
    post preview_admin_messages_path, params: draft

    expect(response).to have_http_status(:ok)
    expect(response.body[/<iframe id="email-preview"[^>]*srcdoc="([^"]*)"/, 1]).to include("dir=&quot;auto&quot;")
    expect(AdminOutreach.count + ActionMailer::Base.deliveries.size).to eq(0)
  end

  it "sends a test email only to the signed-in admin, recording nothing" do
    post test_admin_messages_path, params: draft

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ admin.email ] ])
    expect(AdminOutreach.count).to eq(0)
  end

  it "won't send without the preview's Send button" do
    post admin_messages_path, params: draft
    expect(AdminOutreach.count).to eq(0)
  end

  it "sends from Send, delivers, audits, and shows it in both histories" do
    perform_enqueued_jobs { post admin_messages_path, params: draft.merge(send: "1") }

    expect(response).to redirect_to(admin_messages_path)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ user.email ] ])
    expect(AdminAuditLog.where(action: "message_user", target: user)).to exist

    get admin_messages_path
    expect(response.body[%r{<table id="message-history".*?</table>}m]).to include("About your listing").and include("Email: sent")
    get admin_user_path(user)
    expect(response.body[%r{<table id="user-message-history".*?</table>}m]).to include("email sent")
  end

  # The gate, through the real form: a tampered channels[]=in_app must not
  # create a support thread for a user who may still be on v1.0.4.
  it "refuses a tampered in-app send while the gate is closed, creating nothing" do
    post admin_messages_path, params: draft.merge(channels: %w[in_app], send: "1")

    expect(response).to have_http_status(:unprocessable_content)
    expect(Conversation.kind_support.count).to eq(0)
    expect(AdminOutreach.count).to eq(0)
  end

  # Owner: "for one user we dont need 4". One known reader, one box in their
  # language, no fallback; the four-language system is bulk-only.
  it "has ONE message box, says which language to write in, and no fallback" do
    user.update!(preferred_language: "ps")

    get new_admin_message_path(user_id: user.id)

    expect(response.body).to include("Zarmina reads Pashto: write in Pashto")
    expect(response.body.scan('name="body"').size).to eq(1)
    expect(response.body).not_to include("fallback-locale")
    expect(response.body).not_to include('data-locale="en"')
    expect(response.body[/<textarea[^>]*name="body"[^>]*>/]).to include('dir="rtl"')
  end

  it "delivers the one box as the recipient's own language, with no subject for in-app" do
    user.update!(preferred_language: "ps")
    Conversation.support_thread_for!(user)

    post admin_messages_path, params: { user_id: user.id, channels: %w[in_app], body: "پښتو متن", send: "1" }

    expect(AdminOutreach.last).to have_attributes(locale: "ps", subject: nil, body: "پښتو متن")
  end

  it "records Support-inbox replies in the same history" do
    thread = Conversation.support_thread_for!(user) # the user opened support

    post reply_admin_support_conversation_path(thread), params: { body: "We're on it" }

    get admin_messages_path
    expect(response.body).to include("(support inbox)").and include("We&#39;re on it")
  end

  it "works with CSRF on, using the token the form carries" do
    ActionController::Base.allow_forgery_protection = true
    get new_admin_message_path(user_id: user.id)
    token = response.body[%r{<form[^>]*id="message-form".*?</form>}m][/name="authenticity_token" value="([^"]+)"/, 1]

    post test_admin_messages_path, params: draft.merge(authenticity_token: token)
    expect(response).to have_http_status(:ok)
    post admin_messages_path, params: draft.merge(send: "1", authenticity_token: token)
    expect(response).to redirect_to(admin_messages_path)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  describe "the four buttons" do
    it "shows Send mail / Send message / Send bulk mail / Send bulk message" do
      get admin_messages_path

      %w[send-mail send-message send-bulk-mail send-bulk-message].each { |id| expect(response.body).to include(%(id="#{id}")) }
    end

    it "Send mail: one box with a subject, no channel choice" do
      get new_admin_message_path(user_id: user.id, mode: "email")

      expect(response.body).to include(">Send mail</h1>").and include('name="subject"')
      expect(response.body).not_to include('id="channel-in_app"')
    end

    # Owner: "for message we did not need subject".
    it "Send message: one box, NO subject, no channel choice" do
      get new_admin_message_path(user_id: user.id, mode: "in_app")

      expect(response.body).to include(">Send message</h1>")
      expect(response.body).not_to include('name="subject"')
      expect(response.body).not_to include('id="channel-email"')
    end

    it "keeps the mode through search and the recipient link" do
      user
      get new_admin_message_path(mode: "in_app", q: "Zarmina")

      expect(response.body).to include("mode=in_app")
    end

    it "Send message sends in-app only, even if channels[] is tampered" do
      Conversation.support_thread_for!(user)

      post admin_messages_path, params: { user_id: user.id, mode: "in_app", channels: %w[email in_app],
                                          body: "سلام", send: "1" }

      expect(AdminOutreach.last).to have_attributes(via_in_app: true, via_email: false)
    end

    it "says, without blocking, when the user hasn't used the new app yet" do
      Conversation.support_thread_for!(user)

      get new_admin_message_path(user_id: user.id, mode: "in_app")

      expect(response.body).to include('id="old-app-note"')
      expect(response.body).not_to include('id="mode-refusal"')
    end
  end

  # Owner: "we dont have well preview of this messages or mail when its send …
  # to know which lang it was send etc and can read message".
  describe "viewing a sent message in full" do
    let(:long_body) { "سلام — #{'دا یو اوږد پیغام دی. ' * 20}پای" }

    it "shows the language, the whole body, and the email exactly as sent" do
      user.update!(preferred_language: "ps")
      perform_enqueued_jobs do
        post admin_messages_path, params: draft.merge(mode: "email", subject: "ستاسو حساب", body: long_body, send: "1")
      end
      outreach = AdminOutreach.last

      get admin_message_path(outreach)

      expect(response).to have_http_status(:ok)
      expect(response.body[%r{<span id="outreach-language">.*?</span>}m]).to include("Pashto")
      srcdoc = CGI.unescapeHTML(response.body[/<iframe id="email-preview"[^>]*srcdoc="([^"]*)"/, 1])
      expect(srcdoc).to include(long_body).and include('dir="auto"')
    end

    it "shows an in-app-only message in full, with a link to its conversation" do
      thread = Conversation.support_thread_for!(user)
      post admin_messages_path, params: { user_id: user.id, mode: "in_app", body: long_body, send: "1" }

      get admin_message_path(AdminOutreach.last)

      expect(response.body[%r{<div id="in-app-sent".*?</div>}m]).to include(long_body)
      expect(response.body).not_to include('id="email-preview"')
      expect(response.body).to include(admin_support_conversation_path(thread))
    end

    it "the history row shows the language and opens the full view" do
      user.update!(preferred_language: "ps")
      post admin_messages_path, params: draft.merge(mode: "email", send: "1")

      get admin_messages_path

      expect(response.body).to include('class="hw-sub outreach-language">Pashto')
      expect(response.body).to include(admin_message_path(AdminOutreach.last))
    end

    it "is a 404 for an unknown message" do
      get admin_message_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
