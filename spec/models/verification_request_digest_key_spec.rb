require "rails_helper"

# The ID-number digest key (owner, 2026-10-09: production verification failed
# with "VERIFICATION_NUMBER_HMAC_KEY is not set"). Production reads ENV, then
# credentials; every other environment derives its own key, even when the shared
# credentials file holds the production one.
RSpec.describe VerificationRequest, ".number_digest_key" do
  let(:prod_key) { "p" * 64 }
  let(:env_key) { "e" * 64 }
  let(:production) { ActiveSupport::EnvironmentInquirer.new("production") }

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:verification, :number_hmac_key).and_return(prod_key)
  end

  around do |example|
    saved = ENV.delete("VERIFICATION_NUMBER_HMAC_KEY")
    example.run
  ensure
    saved ? ENV["VERIFICATION_NUMBER_HMAC_KEY"] = saved : ENV.delete("VERIFICATION_NUMBER_HMAC_KEY")
  end

  it "uses the credentials key in production" do
    allow(Rails).to receive(:env).and_return(production)
    expect(described_class.number_digest_key).to eq(prod_key)
  end

  it "prefers ENV over credentials in production" do
    allow(Rails).to receive(:env).and_return(production)
    ENV["VERIFICATION_NUMBER_HMAC_KEY"] = env_key
    expect(described_class.number_digest_key).to eq(env_key)
  end

  it "raises in production when neither ENV nor credentials hold a key" do
    allow(Rails).to receive(:env).and_return(production)
    allow(Rails.application.credentials).to receive(:dig).with(:verification, :number_hmac_key).and_return(nil)
    expect { described_class.number_digest_key }.to raise_error(/VERIFICATION_NUMBER_HMAC_KEY is not set/)
  end

  it "never uses the production key outside production, even when credentials hold it" do
    key = described_class.number_digest_key
    expect(key).not_to eq(prod_key)
    expect(key).to eq(Rails.application.key_generator.generate_key("verification/number_digest", 32))
  end
end
