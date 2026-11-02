require "rails_helper"

# d0 security review 2026-10-09 (Sign in with Apple, dcbf2a5).
RSpec.describe Apple::IdentityToken do
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:raw_nonce) { "raw-nonce" }
  let(:jwks_body) { { keys: [ JWT::JWK.new(rsa, kid: "real-kid").export.merge(alg: "RS256", use: "sig") ] }.to_json }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  def token(kid:)
    claims = { iss: "https://appleid.apple.com", aud: "com.hatiwal.app", sub: "s", email: "a@b.c",
               nonce: Digest::SHA256.hexdigest(raw_nonce), iat: Time.now.to_i, exp: 10.minutes.from_now.to_i }
    JWT.encode(claims, rsa, "RS256", { kid: kid })
  end

  # A token naming an unknown key id purged the cache and refetched Apple's keys
  # EVERY time: forged tokens (anyone can make one) turned each sign-in attempt
  # into an outbound request to Apple.
  it "a burst of tokens with unknown key ids fetches Apple's keys at most once more" do
    fetches = stub_request(:get, described_class::JWKS_URL).to_return(status: 200, body: jwks_body)
    expect(described_class.verify(token(kid: "real-kid"), raw_nonce: raw_nonce)).to be_present
    5.times { |i| expect(described_class.verify(token(kid: "forged-#{i}"), raw_nonce: raw_nonce)).to be_nil }
    expect(fetches).to have_been_requested.at_most_times(2)
  end

  # A network failure reaching Apple raised out of #verify (only JWT/JSON errors
  # were rescued): the sign-in answered 500 instead of 'invalid token'.
  it "a network failure fetching Apple's keys is a rejection (nil), never an exception" do
    stub_request(:get, described_class::JWKS_URL).to_timeout
    expect { described_class.verify(token(kid: "real-kid"), raw_nonce: raw_nonce) }.not_to raise_error
    expect(described_class.verify(token(kid: "real-kid"), raw_nonce: raw_nonce)).to be_nil
  end
end
