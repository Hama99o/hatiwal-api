FactoryBot.define do
  # IDEA-9: a chunked video upload, nothing sent yet.
  factory :resumable_upload do
    association :user
    key { SecureRandom.uuid }
    purpose { :listing_video }
    size { 1_000 }
    sha256 { Digest::SHA256.hexdigest("x" * 1_000) }
  end
end
