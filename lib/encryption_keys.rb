# Which Active Record Encryption keys this environment uses (VER-1).
#
# Production: credentials (`active_record_encryption`), else ENV
# (ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT),
# else none (saving a verification request then raises, by design).
#
# Everywhere else: ENV if set, else keys derived from this environment's
# secret_key_base. Credentials are IGNORED outside production: the credentials
# file is shared by every environment, so honouring it would put the production
# keys on every dev machine and container, and re-key every dev/QA database
# whose rows were encrypted with the derived keys (e693ca2 did exactly that).
module EncryptionKeys
  ENV_KEYS = {
    primary_key: "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
    deterministic_key: "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  DERIVED_PURPOSES = { primary_key: "primary", deterministic_key: "deterministic", key_derivation_salt: "salt" }.freeze

  # Returns { primary_key:, deterministic_key:, key_derivation_salt: } or nil.
  def self.resolve(production:, credentials:, env:, key_generator:)
    if production && credentials.present?
      credentials.to_h.symbolize_keys.slice(*ENV_KEYS.keys)
    elsif env[ENV_KEYS[:primary_key]].present?
      ENV_KEYS.transform_values { |name| env.fetch(name) }
    elsif !production
      DERIVED_PURPOSES.transform_values do |purpose|
        key_generator.generate_key("active_record_encryption/#{purpose}", 32).unpack1("H*")
      end
    end
  end
end
