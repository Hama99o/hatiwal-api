FactoryBot.define do
  factory :verification_request do
    transient do
      user { association :user, :verification_eligible }
    end

    subject { user }
    requested_by { user }
    status { :requested }
    # Owner, 2026-10-05: only the e-Tazkira (two-sided) is accepted.
    document_type { :e_tazkira }
    name_on_document { user.full_name }
    document_number { "1234564821" }

    after(:build) do |request|
      %i[front back selfie].each do |name|
        request.public_send(name).attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
                                         filename: "#{name}.jpg", content_type: "image/jpeg")
      end
    end

    # Kept for older specs: the default is already two-sided now.
    trait :two_sided

    # A paper Tazkira, passport… from before the e-Tazkira-only rule (old rows).
    trait :legacy_document do
      document_type { :tazkira }
      to_create { |request| request.save!(validate: false) }
    end
  end
end
