# Search by image (docs/IMAGE_SEARCH.md).
module ImageSearch
  # On when the model file is on this server, unless IMAGE_SEARCH_ENABLED=0
  # (the kill switch). The apps read it from GET /app_config and hide the camera
  # button when it is off, so an API without the model never offers the feature.
  #
  # config.x.image_search_enabled = false (the test environment) keeps every
  # other spec exactly as it was: no embed job is enqueued for their photos.
  # Specs of this feature turn it on with the :image_search tag.
  def self.enabled?
    return false if ENV["IMAGE_SEARCH_ENABLED"] == "0"
    return false if Rails.configuration.x.image_search_enabled == false

    Embedder.available?
  end
end
