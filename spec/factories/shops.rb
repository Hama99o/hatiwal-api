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
    # Distinct per shop: one owner's shops with the same address are duplicates (SHOP-2).
    sequence(:address_line) { |n| "Near Kabul Bank, shop #{n}" }
    phone { "+93 70 123 4567" }
    hours { { "sat" => [ %w[08:00 18:00] ], "fri" => [] } }

    # SHOP-MEDIA: a real (2 s) MP4 + poster, and two gallery photos in order.
    trait :with_video do
      after(:create) do |shop|
        shop.video.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_video.mp4")),
                          filename: "test_video.mp4", content_type: "video/mp4", metadata: { "duration" => 2.0 })
        shop.video_poster.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                                 filename: "poster.jpg", content_type: "image/jpeg")
      end
    end

    trait :with_gallery do
      after(:create) do |shop|
        %w[front.jpg team.jpg].each_with_index do |name, i|
          blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")),
                                                        filename: name, content_type: "image/jpeg", metadata: { "position" => i })
          shop.gallery_photos.attach(blob)
        end
      end
    end

    trait :suspended do
      status { :suspended }
    end

    # Logo + a live product: what Shop#verification_missing asks for.
    trait :verification_eligible do
      association :owner, factory: %i[user confirmed]
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
    # Owner, 2026-10-05: exactly the person's form for the OWNER + a proof of business.
    document_type { :e_tazkira }
    name_on_document { shop.owner.full_name }
    document_number { "1234564821" }

    after(:build) do |request|
      %i[front back selfie proof].each do |name|
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
