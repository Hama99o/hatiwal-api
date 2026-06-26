class SavedSearchSerializer < ApplicationSerializer
  fields :id, :location, :price_min, :price_max, :latitude, :longitude, :radius,
         :created_at, :last_viewed_at

  field(:category_id) { |ss| ss.category_id }
  field(:category_name) { |ss| ss.category&.name_en }
  field(:location_based) { |ss| ss.location_based? }
  field(:new_matches_count) { |ss| ss.new_matches_count }
end
