require "rails_helper"

# A blob whose file is missing from storage must be a 404, never a 500.
#
# The QA environment produced 14 HTTP 500s in 40 minutes from 5 dangling blobs:
# ActiveStorage::FileNotFoundError out of the variant redirect controller, which
# Rails maps to 500 unless told otherwise. The mobile client cannot tell "the
# server is broken" from "this image is gone" — it reports a network error either
# way — so a listing with one lost photo looked like an API outage.
#
# This matters beyond QA: object storage losing a file, or a restore that brings
# back rows without their blobs, must degrade to a missing image.
RSpec.describe "ActiveStorage with a missing file", type: :request do
  let(:listing) { create(:listing) }

  before do
    listing.images.attach(
      io: Rails.root.join("spec/fixtures/files/test_image.jpg").open,
      filename: "gone.jpg",
      content_type: "image/jpeg"
    )
  end

  it "returns 404 for a variant of a blob whose file was deleted" do
    blob = listing.images.first.blob
    blob.service.delete(blob.key)
    expect(blob.service.exist?(blob.key)).to be false

    get rails_representation_path(
      blob.variant(resize_to_limit: [ 600, 600 ]),
      only_path: true
    )

    expect(response).to have_http_status(:not_found)
  end

  # Counterpart to the above, so the 404 cannot pass by breaking normal serving.
  # It asks for the BLOB, not a variant: variant processing needs an image
  # processor that is not configured in the test environment (vips/mini_magick →
  # "undefined method 'new' for nil"), and that has nothing to do with this
  # mapping. The 404 case never reaches the processor — it raises
  # FileNotFoundError first — which is why only this direction needs avoiding it.
  it "still serves a blob whose file is present" do
    blob = listing.images.first.blob
    expect(blob.service.exist?(blob.key)).to be true

    get rails_blob_path(blob, only_path: true)

    expect(response).to have_http_status(:redirect)
  end
end
