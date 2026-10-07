# The ONE way an admin sends something to one person: by email, in the app as
# Hatiwal Support, or both. Used by the Messages screen and by replies inside a
# support thread, so both land in the same history (AdminOutreach).
#
# Every check runs BEFORE anything is written. If any chosen channel is refused,
# nothing is sent on any channel. In particular, the in-app channel goes through
# Conversation.admin_support_thread_for, the gate (docs/SUPPORT_MESSAGING.md):
# a tampered form can't create a support thread for a user still on v1.0.4.
class Admin::SendMessage
  CHANNELS = %w[email in_app].freeze

  attr_reader :errors, :outreach, :languages

  # content: { "en" => { "subject", "body" }, "ps" => {…}, … } — the person
  # gets the version in their preferred_language, else `fallback_locale`.
  # A subject is part of a version only when emailing (in-app has none).
  def initialize(admin:, user:, channels:, content:, fallback_locale: "en", source: :compose, opt_out_acknowledged: false)
    @admin = admin
    @user = user
    @channels = Array(channels).map(&:to_s) & CHANNELS
    @languages = Admin::LanguageVersions.new(content, fallback: fallback_locale, subject: email?)
    @source = source
    @opt_out_acknowledged = ActiveModel::Type::Boolean.new.cast(opt_out_acknowledged) || false
    @errors = []
  end

  # A support-thread reply: one body, written for this person, in their language.
  def self.reply(admin:, user:, body:)
    locale = user.preferred_language.presence_in(Admin::LanguageVersions::LOCALES) || "en"
    new(admin: admin, user: user, channels: %w[in_app], content: { locale => { "body" => body } },
        fallback_locale: locale, source: :support_inbox)
  end

  def email? = @channels.include?("email")
  def in_app? = @channels.include?("in_app")

  # The version THIS person gets, and its language.
  def locale = @languages.locale_for(@user.preferred_language)
  def subject = @languages.for(@user.preferred_language)&.dig("subject").to_s
  def body = @languages.for(@user.preferred_language)&.dig("body").to_s

  # Validates without writing anything — the compose/preview steps use it.
  def valid?
    @errors = []
    @errors << "Choose at least one channel." if @channels.empty?
    if (missing = @languages.fallback_error)
      @errors << missing
    else
      @errors << "Message is too long (#{body_max} characters max)." if body.length > body_max
    end
    validate_email if email?
    validate_in_app if in_app?
    @errors.empty?
  end

  def call
    return false unless valid?

    ActiveRecord::Base.transaction do
      email = create_email if email?
      message = create_in_app_message if in_app?
      @outreach = AdminOutreach.create!(
        admin_user: @admin, user: @user, via_email: email?, via_in_app: in_app?, locale: locale,
        subject: (subject if email?), body: body, admin_email: email, message: message,
        push_note: (push_note if in_app?), source: @source, opt_out_acknowledged: opted_out? && @opt_out_acknowledged
      )
    end
    deliver
    true
  end

  # Shown at compose time, before anything is sent.
  def push_note
    return "push queued" if @user.push_token.present?

    reason = @user.push_registration_error.presence
    "no push token#{": #{reason}" if reason}"
  end

  def opted_out? = @user.email_opt_out_at.present?

  private

  def validate_email
    @errors << "Email: #{@user.email_refusal_reason}." unless @user.emailable?
    @errors << "Subject is too long (#{AdminEmail::SUBJECT_MAX} characters max)." if subject.length > AdminEmail::SUBJECT_MAX
    return unless opted_out? && !@opt_out_acknowledged

    @errors << "This user unsubscribed from bulk email. Tick the box to confirm this one-to-one email is about their account."
  end

  def validate_in_app
    refusal = Conversation.admin_message_refusal(@user)
    @errors << "In-app: #{refusal}." if refusal
    thread = Conversation.person_support.find_by(buyer_id: @user.id)
    @errors << "In-app: the support conversation is closed. Reopen it first." if thread&.closed?
  end

  # An in-app message is a chat Message (1000 chars); email allows more. When
  # both are ticked, the stricter limit applies to the shared text.
  def body_max = in_app? ? Message::BODY_MAX : AdminEmail::BODY_MAX

  def create_email
    AdminEmail.create!(user: @user, admin_user: @admin, subject: subject, body: body, locale: locale)
  end

  def create_in_app_message
    # The gate — never the ungated user-side creator (spec/models/support_gate_spec.rb).
    thread = Conversation.admin_support_thread_for(@user)
    # Unreachable after validate_in_app; if it ever happens, fail loudly and roll
    # back the whole send rather than deliver half of it.
    raise ArgumentError, "support gate refused user #{@user.id}" unless thread

    thread.messages.create!(user: thread.support_user, admin_user: @admin, kind: :text, body: body)
  end

  def deliver
    @outreach.admin_email&.deliver_later!
    return unless (message = @outreach.message)

    BroadcastMessageJob.perform_later(message.id)
    SendMessagePushJob.perform_later(message.id)
  end
end
