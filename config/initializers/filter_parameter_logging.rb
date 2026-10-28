# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # VER-1: the full ID document number never reaches a log.
  :document_number,
  # The cable's connect URL (privacy review 2026-10-28): the single-use ticket, and
  # the legacy session's uid (the email; access_token is already covered by :token).
  :ticket, :uid
]
