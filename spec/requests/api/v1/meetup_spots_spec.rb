require "swagger_helper"

# IDEA-6: the busy public places the meetup sheet suggests. Public (a guest can
# read them), tiny, cacheable; only rows an admin switched on.
RSpec.describe "Api::V1::MeetupSpots", type: :request do
  path "/api/v1/meetup_spots" do
    get "busy public places to suggest for a meetup" do
      tags "Meetup spots"
      description "IDEA-6: active meetup spots (malls, bazaars) in every city, ordered by city then position. Public. " \
                  "The client shows the ones near the listing. A row is shown only after an admin switched it on."
      produces "application/json"

      response "200", "the active spots" do
        let!(:shown)  { create(:meetup_spot, name_en: "Majid Mall", latitude: 34.53399, longitude: 69.17285) }
        let!(:hidden) { create(:meetup_spot, name_en: "Draft Bazaar", active: false, needs_local_check: true) }

        schema type: :object, properties: {
          meetup_spots: { type: :array, items: { type: :object, properties: {
            id: { type: :integer }, city_key: { type: :string }, kind: { type: :string },
            name_en: { type: :string }, name_ps: { type: :string, nullable: true }, name_fa: { type: :string, nullable: true },
            name_ur: { type: :string, nullable: true }, latitude: { type: :number }, longitude: { type: :number }
          }, required: %w[id city_key kind name_en latitude longitude] } }
        }, required: %w[meetup_spots]

        run_test! do
          spots = response.parsed_body["meetup_spots"]
          expect(spots.map { |s| s["name_en"] }).to eq([ "Majid Mall" ])
          expect(spots.first).to include("latitude" => 34.53399, "longitude" => 69.17285, "kind" => "mall")
          expect(spots.first).not_to have_key("needs_local_check")
          expect(response.headers["Cache-Control"]).to include("public")
        end
      end
    end
  end
end
