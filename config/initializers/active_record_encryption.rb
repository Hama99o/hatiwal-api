# Active Record Encryption keys (VER-1: VerificationRequest#document_number).
#
# Production: the keys come from credentials (`active_record_encryption`, made
# with `bin/rails db:encryption:init`) or from ENV
# (ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT).
# They are NEVER in the repo or the database: a stolen database or backup shows
# only ciphertext. Without them, saving a verification request in production
# raises (ActiveRecord::Encryption::Errors::Configuration), by design.
#
# Development and test: no secrets to manage. Keys are derived from this
# environment's secret_key_base, so they exist only where that secret does and
# are useless against production data.
Rails.application.config.to_prepare do
  credentials = Rails.application.credentials.active_record_encryption
  env_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]

  if credentials.present?
    next # Rails reads credentials.active_record_encryption by itself.
  elsif env_key.present?
    ActiveRecord::Encryption.configure(
      primary_key: env_key,
      deterministic_key: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"),
      key_derivation_salt: ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
    )
  elsif !Rails.env.production?
    derive = ->(purpose) { Rails.application.key_generator.generate_key("active_record_encryption/#{purpose}", 32).unpack1("H*") }
    ActiveRecord::Encryption.configure(
      primary_key: derive.call("primary"),
      deterministic_key: derive.call("deterministic"),
      key_derivation_salt: derive.call("salt")
    )
  else
    Rails.logger.error("[encryption] No Active Record Encryption keys: verification requests cannot be saved. See config/initializers/active_record_encryption.rb")
  end
end
