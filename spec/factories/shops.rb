FactoryBot.define do
  # SHOP-1. Herat by default (inside the service area); `after_create` on Shop
  # adds the owner's ShopMember row.
  factory :shop do
    association :owner, factory: :user
    category
    sequence(:name) { |n| "Safi Cosmetics #{n}" }
    description { "Beauty products, Shar-e-Naw" }
    latitude { 34.3529 }
    longitude { 62.204 }
    address_line { "Near Kabul Bank, 3rd floor" }
    phone { "+93 70 123 4567" }
    hours { { "sat" => [ %w[08:00 18:00] ], "fri" => [] } }

    trait :suspended do
      status { :suspended }
    end

    # Logo + a live product: what Shop#verification_missing asks for.
    trait :verification_eligible do
      after(:create) do |shop|
        shop.logo.attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")
        FactoryBot.create(:listing, :active, user: shop.owner, shop: shop)
      end
    end
  end

  # A shop's application (VER-1 model, SHOP-1 rules): shop front + licence + phone.
  factory :shop_verification_request, class: VerificationRequest.name do
    transient do
      shop { association :shop, :verification_eligible }
    end

    subject { shop }
    requested_by { shop.owner }
    status { :requested }
    # Owner, 2026-10-05: the owner's e-Tazkira + its number + a proof of business.
    document_type { :e_tazkira }
    document_number { "1234564821" }
    phone { "+93 70 123 4567" }

    after(:build) do |request|
      %i[front back proof].each do |name|
        request.public_send(name).attach(io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
                                         filename: "#{name}.jpg", content_type: "image/jpeg")
      end
    end
  end

  factory :shop_member do
    shop
    user
    role { :staff }
  end
end
