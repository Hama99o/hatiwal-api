FactoryBot.define do
  factory :cable_ticket do
    user
    digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    expires_at { CableTicket::TTL.from_now }

    trait :expired do
      expires_at { 1.second.ago }
    end
  end
end
