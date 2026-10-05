FactoryBot.define do
  # SHOP-3: a plain link invite by default; `email:` makes it an email invite.
  factory :shop_invite do
    shop
    invited_by { shop.owner }
    role { :staff }

    trait :expired do
      after(:create) { |i| i.update_columns(expires_at: 1.minute.ago) }
    end
  end

  factory :shop_audit_event do
    shop
    action { "invited" }
    actor { shop.owner }
  end
end
