# IDEA-9: a chunked upload (ResumableUpload) as the app sees it: its public id (the token, never the row id),
# where to resume, and the declared size.
class UploadSerializer < ApplicationSerializer
  field(:id) { |u| u.token }
  fields :offset, :size
end
