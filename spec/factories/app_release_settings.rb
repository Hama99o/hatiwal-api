FactoryBot.define do
  # UPD-1. 1.1.6 is the first build with the gate; 1.1.7 the first a minimum can name.
  factory :app_release_setting do
    android_released_version { "1.1.7" }
    android_latest_version { "1.1.7" }
    android_min_version { "1.1.6" }
    ios_released_version { "1.1.7" }
    ios_latest_version { "1.1.7" }
    ios_min_version { nil }
  end

  factory :app_update_notice do
    user
    platform { "android" }
    target_version { "1.1.7" }
  end
end
