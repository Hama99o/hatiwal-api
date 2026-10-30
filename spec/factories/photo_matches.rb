FactoryBot.define do
  # IDEA-5: `listing` (the newer) reuses a photo of `matched_listing` (another account's, older).
  factory :photo_match do
    association :listing, factory: %i[listing active]
    association :matched_listing, factory: %i[listing active]
    cosine { 0.97 }
    hash_distance { 2 }
    status { :open }
  end
end
