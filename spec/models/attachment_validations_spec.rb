require "rails_helper"

# Active Storage attachments were completely unvalidated: `listing[images][]`,
# `user[avatar]` and a message `attachment` all went straight to Attached#attach,
# so any HTTP client could store a file of any type, of any size, any number of
# times. The only ceiling was the photo picker inside each client, which nothing
# forces a caller to use.
RSpec.describe "Active Storage attachment validations" do
  let(:image_path) { Rails.root.join("spec/fixtures/files/test_image.jpg") }

  def attach_image(attachment, filename: "test_image.jpg")
    attachment.attach(io: File.open(image_path), filename: filename, content_type: "image/jpeg")
  end

  # A ZIP's magic bytes uploaded while CLAIMING to be a JPEG. Active Storage
  # identifies the content type from the file's own bytes (Marcel), not from what
  # the client declared, which is what makes this a real check rather than a
  # filename check — a renamed executable is caught the same way.
  def attach_disguised_zip(attachment)
    attachment.attach(
      io:           StringIO.new("PK\x03\x04#{"\0" * 64}"),
      filename:     "photo.jpg",
      content_type: "image/jpeg"
    )
  end

  # Real JPEG magic bytes followed by padding, so an oversize failure is isolated
  # from a content-type failure. Built at runtime — an oversized fixture has no
  # business being committed to the repo.
  def oversized_jpeg(size)
    file = Tempfile.new([ "big", ".jpg" ])
    file.binmode
    file.write([ 0xFF, 0xD8, 0xFF, 0xE0 ].pack("C*"))
    file.write("\0" * size)
    file.rewind
    file
  end

  describe "Listing#images" do
    let(:listing) { build(:listing) }

    it "accepts a real image" do
      attach_image(listing.images)

      expect(listing).to be_valid
    end

    it "stays valid with no photo at all, so a draft is still saveable" do
      expect(listing).to be_valid
    end

    it "rejects a non-image even when the client declares image/jpeg" do
      attach_disguised_zip(listing.images)

      expect(listing).not_to be_valid
      expect(listing.errors[:images].join).to match(/unsupported file type/)
    end

    it "rejects a photo over the size limit" do
      file = oversized_jpeg(Listing::MAX_IMAGE_SIZE)
      listing.images.attach(io: file, filename: "big.jpg", content_type: "image/jpeg")

      expect(listing).not_to be_valid
      expect(listing.errors[:images].join).to match(/larger than/)
    ensure
      file&.close!
    end

    it "accepts exactly MAX_IMAGES photos" do
      Listing::MAX_IMAGES.times { |i| attach_image(listing.images, filename: "photo#{i}.jpg") }

      expect(listing).to be_valid
    end

    it "rejects more than MAX_IMAGES photos" do
      (Listing::MAX_IMAGES + 1).times { |i| attach_image(listing.images, filename: "photo#{i}.jpg") }

      expect(listing).not_to be_valid
      expect(listing.errors[:images].join).to match(/cannot have more than #{Listing::MAX_IMAGES}/)
    end
  end

  describe "User#avatar" do
    let(:user) { build(:user) }

    it "accepts a real image" do
      attach_image(user.avatar)

      expect(user).to be_valid
    end

    it "rejects a non-image disguised as a JPEG" do
      attach_disguised_zip(user.avatar)

      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/unsupported file type/)
    end

    it "rejects an avatar over the size limit" do
      file = oversized_jpeg(User::MAX_AVATAR_SIZE)
      user.avatar.attach(io: file, filename: "big.jpg", content_type: "image/jpeg")

      expect(user).not_to be_valid
      expect(user.errors[:avatar].join).to match(/larger than/)
    ensure
      file&.close!
    end
  end

  describe "Message#attachment" do
    let(:message) { build(:message) }

    it "accepts an image" do
      attach_image(message.attachment)

      expect(message).to be_valid
    end

    # Documents are allowed here and nowhere else: the :document message kind
    # exists and both clients' pickers offer .pdf/.doc/.docx/.txt.
    it "accepts a plain-text document" do
      message.attachment.attach(
        io: StringIO.new("meetup address"), filename: "note.txt", content_type: "text/plain"
      )

      expect(message).to be_valid
    end

    it "rejects a file type that is neither an image nor an allowed document" do
      attach_disguised_zip(message.attachment)

      expect(message).not_to be_valid
      expect(message.errors[:attachment].join).to match(/unsupported file type/)
    end

    it "rejects an attachment over the size limit" do
      file = oversized_jpeg(Message::MAX_ATTACHMENT_SIZE)
      message.attachment.attach(io: file, filename: "big.jpg", content_type: "image/jpeg")

      expect(message).not_to be_valid
      expect(message.errors[:attachment].join).to match(/larger than/)
    ensure
      file&.close!
    end
  end
end
