require "rails_helper"

RSpec.describe WelcomeSupportMessageJob, type: :job do
  include ActiveJob::TestHelper

  def flag(on, welcome: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return(on ? "true" : "false")
    allow(ENV).to receive(:fetch).with("WELCOME_SUPPORT_MESSAGE", "false").and_return(welcome ? "true" : "false")
  end

  def welcome_for(user) = Conversation.kind_support.find_by(buyer_id: user.id)&.messages&.to_a

  before { flag(true) }

  it "posts one welcome from Hatiwal Support into the user's support thread" do
    user = create(:user, preferred_language: "en")

    described_class.perform_now(user.id)

    messages = welcome_for(user)
    expect(messages.size).to eq(1)
    expect(messages.first.user).to eq(User.support_account!)
    expect(messages.first).to be_text
    expect(messages.first.body).to eq(I18n.t("support.welcome", locale: :en))
    expect(messages.first.read_at).to be_nil
  end

  it "broadcasts it and queues its push, like any Support message" do
    user = create(:user)

    expect { described_class.perform_now(user.id) }
      .to have_enqueued_job(BroadcastMessageJob).and have_enqueued_job(SendMessagePushJob)
  end

  it "writes in the user's own language" do
    %w[ps fa ur].each do |locale|
      user = create(:user, preferred_language: locale)

      described_class.perform_now(user.id)

      expect(welcome_for(user).first.body).to eq(I18n.t("support.welcome", locale: locale))
    end
  end

  it "falls back to the default locale when the user has no language (a Google sign-up)" do
    user = create(:user, preferred_language: nil)

    described_class.perform_now(user.id)

    expect(welcome_for(user).first.body).to eq(I18n.t("support.welcome", locale: I18n.default_locale))
  end

  it "has a welcome text in every supported language" do
    User::SUPPORTED_LANGUAGES.each do |locale|
      expect(I18n.t("support.welcome", locale: locale, raise: true)).to be_present
    end
  end

  it "welcomes only once, even if the job runs again" do
    user = create(:user)

    2.times { described_class.perform_now(user.id) }

    expect(welcome_for(user).size).to eq(1)
  end

  it "sends nothing to a user who already wrote to Support" do
    user = create(:user)
    thread = Conversation.support_thread_for!(user)
    create(:message, conversation: thread, user: user, kind: :text, body: "Hello?")

    expect { described_class.perform_now(user.id) }.not_to change(Message, :count)
  end

  it "sends nothing while SUPPORT_ADMIN_INITIATE is off (the gate), and creates no thread" do
    flag(false)
    user = create(:user)

    described_class.perform_now(user.id)

    expect(Conversation.kind_support.where(buyer_id: user.id)).to be_empty
  end

  it "is OFF by default: nothing is sent and no thread is created (until mobile 1.1.4)" do
    allow(ENV).to receive(:fetch).with("WELCOME_SUPPORT_MESSAGE", "false").and_call_original
    user = create(:user)

    expect(described_class.enabled?).to be(false)
    described_class.perform_now(user.id)

    expect(Conversation.kind_support.where(buyer_id: user.id)).to be_empty
  end

  it "sends nothing while WELCOME_SUPPORT_MESSAGE is off, even with the Support flag on" do
    flag(true, welcome: false)
    user = create(:user)

    described_class.perform_now(user.id)

    expect(Conversation.kind_support.where(buyer_id: user.id)).to be_empty
  end

  it "skips the Support account, a deleted user and a missing id" do
    deleted = create(:user, deleted_at: 1.day.ago)

    expect do
      described_class.perform_now(User.support_account!.id)
      described_class.perform_now(deleted.id)
      described_class.perform_now(-1)
    end.not_to change(Message, :count)
  end
end
