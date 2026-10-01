require "rails_helper"

RSpec.describe "Admin support inbox", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let(:user)  { create(:user, firstname: "Zarmina", lastname: "Khan") }
  let(:thread) { Conversation.support_thread_for!(user) }

  before { sign_in admin, scope: :admin_user }

  def user_says(body, at: Time.current)
    create(:message, conversation: thread, user: user, kind: :text, body: body, created_at: at)
  end

  it "lists support threads, awaiting-reply ones first across the whole list" do
    answered_user = create(:user, firstname: "Answered")
    answered = Conversation.support_thread_for!(answered_user)
    create(:message, conversation: answered, user: answered_user, body: "hi", read_at: Time.current)
    answered.update!(last_message_at: 1.minute.ago)

    user_says("help please")
    thread.update!(last_message_at: 2.days.ago)

    get admin_support_conversations_path

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Zarmina Khan")).to be < response.body.index("Answered")
  end

  # Archive is per side; the user archiving must not touch the admin's view.
  it "still lists and opens a thread the user archived" do
    user_says("help")
    thread.archive_for!(user)

    get admin_support_conversations_path
    expect(response.body).to include("Zarmina Khan")

    get admin_support_conversation_path(thread)
    expect(response).to have_http_status(:ok)
  end

  it "warns the admin when the user can't receive push notifications" do
    user.update!(push_token: nil, last_app_platform: "android")

    get admin_support_conversation_path(thread)

    expect(response.body).to include('id="support-no-push"').and include("no Firebase")
  end

  it "marks the user's messages read when an admin opens the thread" do
    msg = user_says("help")

    get admin_support_conversation_path(thread)

    expect(response.body).to include("help")
    expect(msg.reload.read_at).to be_present
  end

  it "posts a reply as the Support account, records the admin, pushes and audits" do
    expect do
      post reply_admin_support_conversation_path(thread), params: { body: "Try signing out and in again." }
    end.to have_enqueued_job(SendMessagePushJob).and have_enqueued_job(BroadcastMessageJob)

    reply = thread.messages.last
    expect(reply.user).to eq(User.support_account!)
    expect(reply.admin_user).to eq(admin)
    expect(AdminAuditLog.where(action: "support_reply", target: thread)).to exist
  end

  it "refuses a reply on a closed thread" do
    thread.closed!

    post reply_admin_support_conversation_path(thread), params: { body: "hello" }

    expect(thread.messages.count).to eq(0)
  end

  it "closes and reopens" do
    patch close_admin_support_conversation_path(thread)
    expect(thread.reload).to be_closed

    patch reopen_admin_support_conversation_path(thread)
    expect(thread.reload).to be_open
  end

  # Starting a thread from the admin now goes through the Messages screen and
  # its gate: spec/requests/admin/messages_spec.rb and spec/models/support_gate_spec.rb.

  it "the user page links to an existing thread, and says in-app is unavailable while the flag is off" do
    get admin_user_path(create(:user))
    expect(response.body).to include("In-app: not available (needs the app update with support messaging")

    thread
    get admin_user_path(user)
    expect(response.body).to include(admin_support_conversation_path(thread))
  end

  describe "navigation badge" do
    it "counts THREADS awaiting a reply, not messages, on every admin page" do
      chatty = create(:user)
      chatty_thread = Conversation.support_thread_for!(chatty)
      3.times { |i| create(:message, conversation: chatty_thread, user: chatty, body: "hello #{i}") }
      user_says("help")

      get admin_listings_path

      expect(response.body[%r{id="nav-support".*?</a>}m]).to include('class="nav-badge"').and include(">2<")
    end

    it "shows no badge once everything has been read" do
      user_says("help")
      get admin_support_conversation_path(thread) # reading marks it read

      get admin_root_path

      expect(response.body[%r{id="nav-support".*?</a>}m]).not_to include("nav-badge")
    end
  end

  it "paginates the inbox" do
    (Admin::SupportConversationsController::PER_PAGE + 1).times do
      Conversation.support_thread_for!(create(:user))
    end

    get admin_support_conversations_path
    rows = response.body[%r{<tbody>.*?</tbody>}m].scan("<tr ").size
    expect(rows).to eq(Admin::SupportConversationsController::PER_PAGE)
    expect(response.body).to include("page=2")
  end

  it "polls for new messages, and the thread page holds off while a reply is typed" do
    get admin_support_conversations_path
    expect(response.body).to include("window.location.reload()")

    get admin_support_conversation_path(thread)
    expect(response.body).to include("box.value.trim()").and include("Auto-refresh paused")
  end
end
