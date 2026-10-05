# VER-1: what a status card shows for one subject, derived — never stored.
#
#   none      → "Get verified" (with what is still missing, if anything)
#   requested → "Under review · sent <date>"
#   verified  → "Verified ✓ since <date>"
#   rejected  → the reason + Try again
#   revoked   → the reason + Apply again
#
# The badge (users.verified) wins: a badge switched on by hand reads verified
# even without a request. An approved request whose badge was switched off by
# hand reads none.
class VerificationStatus
  STATES = %w[none requested verified rejected revoked].freeze

  attr_reader :subject, :request

  def initialize(subject)
    @subject = subject
    @request = subject.latest_verification_request
  end

  def state
    return "verified" if subject.verified?
    return "none" if request.nil? || request.approved?

    request.status
  end

  def verified_since
    return nil unless state == "verified"

    request&.approved? ? request.decided_at : nil
  end

  def missing = state == "verified" ? [] : subject.verification_missing

  # The reason in the subject's language (the clients also translate
  # reason_code themselves; this is the fallback and the "other" free text).
  def reason
    return nil unless %w[rejected revoked].include?(state)

    request.reason_for(subject.preferred_language.presence || I18n.default_locale)
  end

  # The request shown on the card, if it is the one the state is about.
  def shown_request = %w[requested rejected revoked].include?(state) ? request : nil
end
