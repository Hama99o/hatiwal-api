FactoryBot.define do
  factory :idempotency_key do
    user
    key { SecureRandom.uuid }
    request_fingerprint { Digest::SHA256.hexdigest(SecureRandom.hex) }
    status { :in_progress }

    trait :completed do
      status { :completed }
      response_code { 200 }
      response_body { { "ok" => true } }
    end
  end
end
