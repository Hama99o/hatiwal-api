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
# environment's secret_key_base (ENV still wins), so they exist only where that
# secret does and are useless against production data. Credentials are ignored
# here on purpose — see lib/encryption_keys.rb.
Rails.application.config.to_prepare do
  keys = EncryptionKeys.resolve(
    production: Rails.env.production?,
    credentials: Rails.application.credentials.active_record_encryption,
    env: ENV,
    key_generator: Rails.application.key_generator
  )

  if keys
    ActiveRecord::Encryption.configure(**keys)
  else
    Rails.logger.error("[encryption] No Active Record Encryption keys: verification requests cannot be saved. See config/initializers/active_record_encryption.rb")
  end
end
