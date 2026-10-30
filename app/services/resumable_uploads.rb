# IDEA-9 (1.2.1): chunked video uploads (ResumableUpload). On unless RESUMABLE_UPLOADS_ENABLED=0 — the kill
# switch: the apps read GET /app_config features.resumable_uploads and send today's single PUT when it is off.
module ResumableUploads
  def self.enabled? = ENV["RESUMABLE_UPLOADS_ENABLED"] != "0"
end
