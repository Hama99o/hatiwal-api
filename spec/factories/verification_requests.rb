FactoryBot.define do
  factory :verification_request do
    transient do
      user { association :user, :verification_eligible }
    end

    subject { user }
    requested_by { user }
    status { :requested }
    document_type { :tazkira }
    name_on_document { user.full_name }
    document_last4 { "4821" }

    after(:build) do |request|
      %i[front selfie].each do |name|
        request.public_send(name).attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
                                         filename: "#{name}.jpg", content_type: "image/jpeg")
      end
    end

    trait :two_sided do
      document_type { :e_tazkira }
      after(:build) do |request|
        request.back.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
                            filename: "back.jpg", content_type: "image/jpeg")
      end
    end
  end
end
