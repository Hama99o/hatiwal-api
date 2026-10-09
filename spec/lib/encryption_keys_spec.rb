require "rails_helper"

RSpec.describe EncryptionKeys do
  let(:credentials) { { primary_key: "cred-primary", deterministic_key: "cred-det", key_derivation_salt: "cred-salt" } }
  let(:key_generator) { Rails.application.key_generator }
  let(:derived_primary) { key_generator.generate_key("active_record_encryption/primary", 32).unpack1("H*") }
  let(:env_keys) do
    { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "env-primary",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "env-det",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "env-salt" }
  end

  def resolve(production:, credentials: nil, env: {})
    described_class.resolve(production:, credentials:, env:, key_generator:)
  end

  context "in production" do
    it "uses the credentials keys" do
      expect(resolve(production: true, credentials:, env: env_keys)).to eq(credentials)
    end

    it "falls back to ENV without credentials" do
      expect(resolve(production: true, env: env_keys))
        .to eq(primary_key: "env-primary", deterministic_key: "env-det", key_derivation_salt: "env-salt")
    end

    it "never derives keys (no keys at all → nil)" do
      expect(resolve(production: true)).to be_nil
    end
  end

  context "outside production" do
    it "ignores credentials and derives the keys from secret_key_base" do
      keys = resolve(production: false, credentials:)
      expect(keys[:primary_key]).to eq(derived_primary)
      expect(keys.values).not_to include(*credentials.values)
    end

    it "lets ENV win over the derived keys" do
      expect(resolve(production: false, credentials:, env: env_keys)[:primary_key]).to eq("env-primary")
    end
  end

  it "configures the test env with the derived key, never a key from credentials" do
    expect(ActiveRecord::Encryption.config.primary_key).to eq(derived_primary)
    # Where this checkout can decrypt credentials (a master key is present), they
    # hold the production keys since e693ca2 — and those must not be in use here.
    credentials = Rails.application.credentials.active_record_encryption
    expect(ActiveRecord::Encryption.config.primary_key).not_to eq(credentials[:primary_key]) if credentials.present?
  end
end
