# IDEA-6: what the apps need to suggest a meetup spot — never the admin's
# review state (`active`, `needs_local_check`, `note`).
class MeetupSpotSerializer < ApplicationSerializer
  identifier :id

  fields :city_key, :kind, :name_en, :name_ps, :name_fa, :name_ur

  field(:latitude) { |spot| spot.latitude.to_f }
  field(:longitude) { |spot| spot.longitude.to_f }
end
