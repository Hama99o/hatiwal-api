require "administrate/base_dashboard"

# IDEA-6 (docs/SAFE_MEETUP_SPOTS.md): busy public places suggested for a meetup.
# Malls and big bazaars only. A row shows in the apps only when `active`; the
# seeded draft rows start off and "Needs local check".
class MeetupSpotDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    city_key: Field::Select.with_options(collection: %w[kabul herat kandahar mazar jalalabad], searchable: true),
    name_en: Field::String.with_options(searchable: true),
    name_ps: Field::String,
    name_fa: Field::String,
    name_ur: Field::String,
    kind: Field::Select.with_options(collection: ->(_field) { MeetupSpot.kinds.keys }, searchable: false),
    latitude: Field::Number.with_options(decimals: 6),
    longitude: Field::Number.with_options(decimals: 6),
    position: Field::Number,
    active: Field::Boolean,
    needs_local_check: LocalCheckField,
    note: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[city_key name_en name_fa kind active needs_local_check position].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id city_key name_en name_ps name_fa name_ur kind latitude longitude position
                            active needs_local_check note created_at updated_at].freeze

  FORM_ATTRIBUTES = %i[city_key name_en name_ps name_fa name_ur kind latitude longitude position
                       active needs_local_check note].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(spot)
    "#{spot.name_en} (#{spot.city_key})"
  end
end
