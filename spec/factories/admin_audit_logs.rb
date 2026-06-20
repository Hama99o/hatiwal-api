FactoryBot.define do
  factory :admin_audit_log do
    association :admin_user
    action { "block_user" }
    details { nil }
  end
end
