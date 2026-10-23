require "rails_helper"

# OFFLINE phase 0 (docs/OFFLINE_MODE.md §2.5): Listing#ordered_images and
# #apply_image_order!. The request side is spec/requests/api/v1/my/listing_photo_order_spec.rb.
RSpec.describe Listing, type: :model do
  let(:listing) { create(:listing) }

  def attach(name)
    listing.images.attach(io: StringIO.new(name), filename: name, content_type: "image/jpeg")
    listing.images.attachments.max_by(&:id)
  end

  def names(list) = list.map { |a| a.blob.filename.to_s }

  describe "#ordered_images" do
    it "is empty without photos" do
      expect(listing.ordered_images).to eq([])
    end

    it "is upload order when no position was ever set (every listing before 1.2.0)" do
      %w[a.jpg b.jpg c.jpg].each { |n| attach(n) }

      expect(names(listing.reload.ordered_images)).to eq(%w[a.jpg b.jpg c.jpg])
    end

    it "puts positioned photos first, then the rest in upload order" do
      a = attach("a.jpg")
      attach("b.jpg")
      c = attach("c.jpg")
      c.blob.update!(metadata: c.blob.metadata.merge("position" => 0))
      a.blob.update!(metadata: a.blob.metadata.merge("position" => 1))

      expect(names(listing.reload.ordered_images)).to eq(%w[c.jpg a.jpg b.jpg])
    end
  end

  describe "#apply_image_order!" do
    before { %w[a.jpg b.jpg c.jpg].each { |n| attach(n) } }

    let(:sid) { ->(name) { listing.images.find { |a| a.blob.filename.to_s == name }.blob.signed_id } }

    it "does nothing for nil (an app that does not send the field)" do
      expect { listing.apply_image_order!(nil) }.not_to(change { listing.reload.images.map { |a| a.blob.metadata["position"] } })
    end

    it "keeps the other metadata of the blob" do
      blob = listing.images.first.blob
      blob.update!(metadata: blob.metadata.merge("width" => 640))

      listing.apply_image_order!([ sid.call("c.jpg") ])

      expect(blob.reload.metadata).to include("width" => 640)
    end

    it "is idempotent: the same order twice writes nothing the second time" do
      order = [ sid.call("b.jpg"), sid.call("a.jpg"), sid.call("c.jpg") ]
      listing.apply_image_order!(order)
      listing.reload

      expect_any_instance_of(ActiveStorage::Blob).not_to receive(:update!) # rubocop:disable RSpec/AnyInstance
      listing.apply_image_order!(order)
      expect(names(listing.ordered_images)).to eq(%w[b.jpg a.jpg c.jpg])
    end

    it "drops a duplicated token" do
      listing.apply_image_order!([ sid.call("c.jpg"), sid.call("c.jpg"), sid.call("a.jpg") ])

      expect(names(listing.reload.ordered_images)).to eq(%w[c.jpg a.jpg b.jpg])
    end
  end
end
