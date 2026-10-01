FactoryBot.define do
  factory :admin_email do
    association :admin_user
    association :user
    subject { "About your listing" }
    body    { "Salaam — a quick note from Hatiwal." }
    status  { :queued }
  end
end
