# Active Storage's WRITE endpoints are closed (d0 hunt round 2, 2026-10-11).
#
# POST /rails/active_storage/direct_uploads (create a blob of any declared size)
# and PUT /rails/active_storage/disk/:encoded_token (write its bytes to the Disk
# service) were live, unauthenticated and unthrottled: anyone could fill the
# server's disk. Neither app uses direct uploads — every upload is multipart
# through our own, authenticated controllers — so both answer 404. The READ
# routes (blob / representation redirect, disk GET) and every URL helper are
# untouched. The same pattern as private_verification_files.rb.
#
# PREPENDED: production has forgery protection on, and a plain before_action
# ran after the CSRF check — a request carrying a token scraped from any public
# HTML form would have reached the controller (the prod-image smoke answered
# 422, not 404, 2026-10-12). The guard now runs first, whatever the request.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.prepend_before_action { head :not_found }
  ActiveStorage::DiskController.prepend_before_action(only: :update) { head :not_found }
end
