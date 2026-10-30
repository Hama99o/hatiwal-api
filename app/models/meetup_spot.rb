# IDEA-6 (docs/SAFE_MEETUP_SPOTS.md): a busy public place the meetup sheet
# suggests — a mall entrance or a big bazaar, never a police post, a shrine or
# a bank front. Kept on the admin page "Meetup spots"; shown in the apps only
# once `active`. The starting list is config/meetup_spots.yml, seeded switched
# off and `needs_local_check` until someone local confirms each row.
class MeetupSpot < ApplicationRecord
  SEED_FILE = Rails.root.join("config/meetup_spots.yml")
  LOCALES = %w[en ps fa ur].freeze

  enum :kind, { mall: 0, bazaar: 1 }

  validates :city_key, :name_en, :kind, presence: true
  validates :name_en, uniqueness: { scope: :city_key }
  validates :latitude, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  scope :shown, -> { where(active: true).order(:city_key, :position, :id) }

  # The user's language, then Dari, then English. Urdu falls back to English
  # (Dari script is not Urdu).
  def name_for(locale)
    locale = locale.to_s
    return name_en unless LOCALES.include?(locale)

    fallbacks = locale == "ur" ? [ name_ur, name_en ] : [ public_send(:"name_#{locale}"), name_fa, name_en ]
    fallbacks.find(&:present?)
  end

  # Adds every row of the starting list that is missing (by city + English
  # name), switched off and needing a local check; never edits or deletes a row.
  # Returns the number of rows inserted.
  def self.seed_defaults!(file = SEED_FILE)
    now = Time.current
    rows = YAML.load_file(file).flat_map do |city_key, spots|
      spots.each_with_index.map do |spot, index|
        spot.symbolize_keys.merge(city_key: city_key, kind: kinds.fetch(spot["kind"]), position: index,
                                  active: false, needs_local_check: true, created_at: now, updated_at: now)
      end
    end
    return 0 if rows.empty?

    insert_all(rows, unique_by: %i[city_key name_en]).rows.size
  end
end
