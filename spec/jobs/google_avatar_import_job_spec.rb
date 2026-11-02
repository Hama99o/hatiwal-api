require "rails_helper"

# A NEW account made by Google sign-in takes its Google profile photo as its avatar
# (owner, 2026-10-29), in the background: sign-in never waits for it or fails
# because of it. The URL comes from Google's token payload, so it is fetched as an
# untrusted URL (SSRF): https only, a *.googleusercontent.com host, no redirects,
# short timeouts, at most 5 MB while streaming, an image only; then the avatar's
# own validations. At most 2 attempts; any refusal or failure leaves no avatar.
RSpec.describe GoogleAvatarImportJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, confirmed_at: Time.current) }
  let(:picture) { "https://lh3.googleusercontent.com/a/ACg8ocK-photo=s96-c" }
  let(:sized) { "https://lh3.googleusercontent.com/a/ACg8ocK-photo=s400-c" }
  let(:jpeg) { file_fixture("test_image.jpg").binread }

  def stub_photo(url: sized, status: 200, body: jpeg, headers: { "Content-Type" => "image/jpeg" })
    stub_request(:get, url).to_return(status: status, body: body, headers: headers)
  end

  it "attaches the Google photo, asked at 400 px instead of 96" do
    req = stub_photo
    described_class.perform_now(user.id, picture)
    expect(req).to have_been_requested.once
    expect(user.reload.avatar).to be_attached
    expect(user.avatar.blob.content_type).to eq("image/jpeg")
  end

  it "asks for 400 px when the URL carries no size" do
    req = stub_photo(url: "https://lh3.googleusercontent.com/a/plain=s400-c")
    described_class.perform_now(user.id, "https://lh3.googleusercontent.com/a/plain")
    expect(req).to have_been_requested.once
    expect(user.reload.avatar).to be_attached
  end

  it "leaves an avatar the user set before the job ran" do
    user.avatar.attach(io: StringIO.new(jpeg), filename: "mine.jpg", content_type: "image/jpeg")
    req = stub_photo
    described_class.perform_now(user.id, picture)
    expect(req).not_to have_been_requested
    expect(user.reload.avatar.filename.to_s).to eq("mine.jpg")
  end

  {
    "a non-Google host" => "https://evil.example/a.jpg",
    "a look-alike host" => "https://lh3.googleusercontent.com.evil.example/a.jpg",
    "plain http" => "http://lh3.googleusercontent.com/a/photo=s96-c",
    "another port" => "https://lh3.googleusercontent.com:8443/a/photo=s96-c",
    "credentials in the URL" => "https://user:pw@lh3.googleusercontent.com/a/photo=s96-c",
    "the metadata service" => "http://169.254.169.254/latest/meta-data/",
    "not a URL" => "javascript:alert(1)"
  }.each do |what, url|
    it "refuses #{what} without any request" do
      described_class.perform_now(user.id, url)
      expect(a_request(:any, /.*/)).not_to have_been_made
      expect(user.reload.avatar).not_to be_attached
    end
  end

  it "follows no redirect" do
    stub_photo(status: 302, body: "", headers: { "Location" => "http://169.254.169.254/" })
    described_class.perform_now(user.id, picture)
    expect(a_request(:get, "http://169.254.169.254/")).not_to have_been_made
    expect(user.reload.avatar).not_to be_attached
  end

  it "refuses a file over 5 MB (counted while reading)" do
    stub_photo(body: jpeg + ("\0" * 5.megabytes))
    described_class.perform_now(user.id, picture)
    expect(user.reload.avatar).not_to be_attached
  end

  it "refuses a file whose declared length is over 5 MB" do
    stub_photo(headers: { "Content-Type" => "image/jpeg", "Content-Length" => (6.megabytes).to_s })
    described_class.perform_now(user.id, picture)
    expect(user.reload.avatar).not_to be_attached
  end

  it "refuses what is not an image (declared)" do
    stub_photo(body: "<html>login</html>", headers: { "Content-Type" => "text/html" })
    described_class.perform_now(user.id, picture)
    expect(user.reload.avatar).not_to be_attached
  end

  it "refuses what is not an image (declared image/jpeg, the bytes say otherwise)" do
    stub_photo(body: file_fixture("not_an_image.zip").binread)
    described_class.perform_now(user.id, picture)
    expect(user.reload.avatar).not_to be_attached
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it "tries at most twice on a network failure, then gives up quietly" do
    req = stub_request(:get, sized).to_timeout
    perform_enqueued_jobs { described_class.perform_later(user.id, picture) }
    expect(req).to have_been_requested.twice
    expect(user.reload.avatar).not_to be_attached
    expect(user).to be_active
  end

  it "does nothing for an account gone in the meantime" do
    req = stub_photo
    described_class.perform_now(0, picture)
    expect(req).not_to have_been_requested
  end
end
