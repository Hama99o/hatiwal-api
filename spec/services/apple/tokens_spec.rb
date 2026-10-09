require "rails_helper"

# Revoking a deleted account's Apple authorization (App Store guideline
# 5.1.1(v)): POST appleid.apple.com/auth/revoke with a client-secret JWT signed
# by the Sign-in-with-Apple key. Not configured → a logged no-op.
RSpec.describe Apple::Tokens do
  let(:ec) { OpenSSL::PKey::EC.generate("prime256v1") }
  let(:configured) do
    { team_id: "TEAM123456", key_id: "KEY1234567", client_id: "com.hatiwal.app", private_key: ec.to_pem }
  end

  describe ".revoke" do
    it "posts the refresh token with an ES256 client secret (iss team, sub client, aud Apple)" do
      allow(Apple::Config).to receive(:settings).and_return(configured)
      call = stub_request(:post, described_class::REVOKE_URL)
             .with(body: hash_including("token" => "r-tok-1", "token_type_hint" => "refresh_token",
                                        "client_id" => "com.hatiwal.app"))
             .to_return(status: 200, body: "")
      expect(described_class.revoke("r-tok-1")).to be(true)
      expect(call).to have_been_requested

      secret = nil
      expect(a_request(:post, described_class::REVOKE_URL).with { |r| secret = URI.decode_www_form(r.body).to_h["client_secret"] })
        .to have_been_made
      claims, header = JWT.decode(secret, ec, true, algorithm: "ES256")
      expect(header).to include("kid" => "KEY1234567", "alg" => "ES256")
      expect(claims).to include("iss" => "TEAM123456", "sub" => "com.hatiwal.app", "aud" => "https://appleid.apple.com")
    end

    it "is a no-op that logs a warning when the key is not configured" do
      allow(Apple::Config).to receive(:settings).and_return({})
      expect(Rails.logger).to receive(:warn).with(/Sign in with Apple.*not configured/)
      expect(described_class.revoke("r-tok-1")).to be(false)
      expect(a_request(:post, described_class::REVOKE_URL)).not_to have_been_made
    end

    it "returns false (logged) when Apple answers an error" do
      allow(Apple::Config).to receive(:settings).and_return(configured)
      stub_request(:post, described_class::REVOKE_URL).to_return(status: 400, body: { error: "invalid_client" }.to_json)
      expect(described_class.revoke("r-tok-1")).to be(false)
    end
  end

  describe "account deletion" do
    include ActiveJob::TestHelper

    it "revokes the Apple authorization and forgets the Apple id + token" do
      user = create(:user, :confirmed, apple_uid: "001.abc.002", apple_refresh_token: "r-tok-9")
      expect { user.anonymize_account! }.to have_enqueued_job(AppleRevokeJob)
      expect(user.reload).to have_attributes(apple_uid: nil, apple_refresh_token: nil)

      allow(Apple::Config).to receive(:settings).and_return(configured)
      revoke = stub_request(:post, described_class::REVOKE_URL)
               .with(body: hash_including("token" => "r-tok-9")).to_return(status: 200, body: "")
      perform_enqueued_jobs(only: AppleRevokeJob)
      expect(revoke).to have_been_requested
    end

    it "enqueues nothing for an account that never used Apple" do
      user = create(:user, :confirmed)
      expect { user.anonymize_account! }.not_to have_enqueued_job(AppleRevokeJob)
    end
  end
end
