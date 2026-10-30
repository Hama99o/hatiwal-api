FactoryBot.define do
  factory :message do
    association :conversation
    association :user

    body { Faker::Lorem.sentence }
    kind { :text }

    trait :deleted do
      deleted_at { Time.current }
    end

    # SF-B11 — an offer. The body carries the pipe encoding the serializer parses
    # `offer_amount`/`offer_currency` out of ("amount|currency|listedPrice").
    #
    # `offer_quantity` is deliberately LEFT NIL here: nil means "the sender said
    # nothing about how many", which is what every offer in the app is until a
    # client starts sending one, and every spec that does not care about quantity
    # must keep exercising exactly that row. Set it explicitly where it matters.
    # Voice messages (1.2.1): what the server stores after re-encoding — an
    # m4a, its measured duration and waveform, and the "🎤 m:ss" body.
    trait :voice do
      kind { :voice_message }
      body { "🎤 0:12" }
      voice_duration_ms { 12_000 }
      voice_waveform { Array.new(64, 40) }
      after(:build) do |m|
        m.attachment.attach(io: StringIO.new("\x00\x00\x00\x18ftypM4A ".b + ("\x00".b * 64)),
                            filename: "voice.m4a", content_type: "audio/mp4", identify: false)
      end
    end

    trait :offer do
      kind { :offer }
      body { "8000|AFN|10000" }
    end

    trait :offer_counter do
      kind { :offer_counter }
      body { "9000|AFN|10000" }
    end
  end
end
