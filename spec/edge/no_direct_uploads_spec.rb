require "rails_helper"

# d0 hunt round 2, 2026-10-11 (supervisor: on the 1.1.6 deploy). Active
# Storage's write endpoints were live, unauthenticated and unthrottled: anyone
# could create a blob of any declared size (POST /rails/active_storage/
# direct_uploads) and PUT its bytes to the Disk service until the VPS disk was
# full. Neither app uses direct uploads (everything is multipart through our
# own controllers), so both write endpoints are closed; every READ route works.
RSpec.describe "Active Storage: no anonymous writes, reads unchanged", type: :request do
  it "direct_uploads is not found" do
    post "/rails/active_storage/direct_uploads",
         params: { blob: { filename: "a.bin", byte_size: 1_000_000_000, checksum: Base64.strict_encode64("x" * 16), content_type: "application/octet-stream" } },
         as: :json
    expect(response).to have_http_status(:not_found)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  # Production has forgery protection on (tests turn it off): the guard must run
  # BEFORE the CSRF check, or a request carrying a token scraped from any
  # public HTML form (e.g. the admin login page) would get through. The smoke
  # of the production image answered 422 here, not 404 (2026-10-12).
  it "is not found with forgery protection ON too (the guard runs before CSRF)" do
    ActionController::Base.allow_forgery_protection = true
    post "/rails/active_storage/direct_uploads",
         params: { blob: { filename: "a.bin", byte_size: 10, checksum: Base64.strict_encode64("x" * 16), content_type: "application/octet-stream" } },
         as: :json
    expect(response).to have_http_status(:not_found)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "the Disk service's PUT is not found" do
    put "/rails/active_storage/disk/anything", params: "bytes", headers: { "Content-Type" => "application/octet-stream" }
    expect(response).to have_http_status(:not_found)
  end

  it "reading a public image still works (blob redirect → disk GET)" do
    user = create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/test_image.jpg")), filename: "a.jpg", content_type: "image/jpeg")
    get Rails.application.routes.url_helpers.rails_blob_path(user.avatar, only_path: true)
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "a multipart upload through our own API still works" do
    user = create(:user)
    file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/test_image.jpg"), "image/jpeg")
    put "/api/v1/users/me", params: { user: { avatar: file } }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:ok)
    expect(user.reload.avatar).to be_attached
  end
end
