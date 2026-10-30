require "rails_helper"

# IDEA-5 scam photo detection (1.2.1, hatiwal-mobile docs/design/SCAM_PHOTO.md §3): a photo of
# one account's listing that is the same photo as another account's LIVE listing flags the NEWER
# listing for an admin. Nothing is blocked or changed; nothing is shown to buyers.
#
# CLIP vectors are fake (fake_vector: exact cosines); the perceptual hashes are REAL, from the
# committed CC0 seed photos and crafted copies of them.
RSpec.describe ScamPhoto::Matcher, :image_search do
  let(:seeds) { Rails.root.join("db/seeds/images") }
  let(:corolla) { File.binread(seeds.join("vehicles/car-corolla-1.jpg")) }
  let(:corolla_copy) { Vips::Image.new_from_buffer(corolla, "").resize(0.4).fliphor.write_to_buffer(".jpg[Q=70]") }
  let(:sedan1) { File.binread(seeds.join("vehicles/car-sedan-1.jpg")) }
  let(:sedan2) { File.binread(seeds.join("vehicles/car-sedan-2.jpg")) }

  let(:alice) { create(:user) }
  let(:bob) { create(:user) }
  let!(:original) { create(:listing, :active, :with_image, user: alice, created_at: 3.days.ago) }
  let!(:copy) { create(:listing, :active, :with_image, user: bob) }

  # The listing's first photo row: a fake CLIP vector and the real hashes of `bytes`.
  def index!(listing, bytes, vector)
    embed_photo!(listing, vector).tap { |row| row.update!(photo_hashes: ScamPhoto::Hasher.hashes(bytes)) }
  end

  def flags_on(listing) = Flag.where(flaggable: listing)

  describe "a copy of another account's photo" do
    before do
      index!(original, corolla, fake_vector(0))
      index!(copy, corolla_copy, fake_vector(0, other: 1, mix: 0.05)) # cosine 0.97
    end

    it "flags the NEWER listing (reused_photo) and records the pair, both photos and the scores" do
      expect { described_class.call(copy) }.to change(PhotoMatch, :count).by(1)

      flag = flags_on(copy).sole
      expect(flag).to have_attributes(source: "reused_photo", status: "open", category: nil)
      match = PhotoMatch.sole
      expect(match).to have_attributes(listing_id: copy.id, matched_listing_id: original.id, flag_id: flag.id, status: "open",
                                       attachment_id: copy.images.attachments.first.id,
                                       matched_attachment_id: original.images.attachments.first.id,
                                       hash_distance: be <= ScamPhoto::Hasher::MATCH_DISTANCE)
      expect(match.cosine).to be_within(0.001).of(Math.sqrt(0.95))
      expect(flags_on(original)).to be_empty
    end

    it "still flags the newer one when the OLDER listing's photo is the one being matched" do
      described_class.call(original)

      expect(flags_on(copy).sole.source).to eq("reused_photo")
      expect(flags_on(original)).to be_empty
      expect(PhotoMatch.sole).to have_attributes(listing_id: copy.id, matched_listing_id: original.id)
    end

    it "joins an open flag the listing already has, and records the pair once" do
      term_flag = create(:flag, flaggable: copy, category: :stolen_goods)

      2.times { described_class.call(copy) }

      expect(flags_on(copy).sole).to eq(term_flag)
      expect(PhotoMatch.sole.flag).to eq(term_flag)
    end

    it "logs the decision with the ids and the scores (no photo)" do
      allow(Rails.logger).to receive(:info).and_call_original

      described_class.call(copy)

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/\[scam_photo\] match listing=#{copy.id} matched=#{original.id} attachment=\d+ matched_attachment=\d+ cosine=0\.97\d* hash=\d+ flag=\d+/))
    end

    it "warns when one photo's comparison is slow (the trigger for pgvector)" do
      stub_const("ScamPhoto::Matcher::SLOW_MS", -1)
      allow(Rails.logger).to receive(:warn).and_call_original

      described_class.call(copy)

      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/\[scam_photo\] slow listing=#{copy.id} attachment=\d+ candidates=1 ms=/))
    end

    it "does nothing when switched off (SCAM_PHOTO_ENABLED=0)" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SCAM_PHOTO_ENABLED").and_return("0")

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end
  end

  describe "not the same photo" do
    it "a different photo of a look-alike product, even at a high CLIP score, is not flagged (logged as a near miss)" do
      index!(original, sedan1, fake_vector(0))
      index!(copy, sedan2, fake_vector(0, other: 1, mix: 0.05))
      allow(Rails.logger).to receive(:info).and_call_original

      expect { described_class.call(copy) }.not_to change(Flag, :count)
      expect(PhotoMatch.count).to eq(0)
      expect(Rails.logger).to have_received(:info).with(a_string_matching(/\[scam_photo\] near listing=#{copy.id} matched=#{original.id} .*hash=\d+/))
    end

    it "the same hashes below the CLIP pre-filter are not compared" do
      index!(original, corolla, fake_vector(0))
      index!(copy, corolla, fake_vector(0, other: 1, mix: 0.5)) # cosine 0.71

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end
  end

  describe "who is never compared" do
    def same_photo!(older, newer)
      index!(older, corolla, fake_vector(0))
      index!(newer, corolla, fake_vector(0))
    end

    it "the same account" do
      own = create(:listing, :active, :with_image, user: bob)
      same_photo!(own, copy)

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end

    it "the same shop's team" do
      shop = create(:shop, owner: alice)
      ShopMember.create!(shop: shop, user: bob, role: :staff)
      same_photo!(original, copy)

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end

    { "a draft" => :draft, "a sold listing" => :sold }.each do |what, status|
      it "#{what} (only live listings are compared)" do
        same_photo!(original, copy)
        original.update_columns(status: Listing.statuses[status])

        expect { described_class.call(copy) }.not_to change(Flag, :count)
      end
    end

    it "a listing an admin removed" do
      same_photo!(original, copy)
      original.update_columns(removed_at: Time.current)

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end

    it "nothing is matched for a listing that is not live itself" do
      same_photo!(original, copy)
      copy.update_columns(status: Listing.statuses[:draft])

      expect { described_class.call(copy) }.not_to change(Flag, :count)
    end
  end

  describe "an admin's decision" do
    let(:admin) { create(:admin_user) }

    before do
      index!(original, corolla, fake_vector(0))
      index!(copy, corolla_copy, fake_vector(0))
      described_class.call(copy)
    end

    it "a dismissed pair is remembered and never flagged again; the older listing is untouched" do
      ProhibitedItems::Moderation.new(flags_on(copy).sole, admin: admin).dismiss!

      expect(PhotoMatch.sole).to be_dismissed
      expect { described_class.call(copy) }.not_to change(Flag, :count)
      expect(flags_on(original)).to be_empty
      expect(original.reload).to be_active
    end

    it "the older listing taken down for something else does not change the newer flag" do
      other_flag = create(:flag, flaggable: original, category: :stolen_goods)
      ProhibitedItems::Moderation.new(other_flag, admin: admin).take_down!

      expect(flags_on(copy).sole).to be_open
      expect(PhotoMatch.sole).to be_open
    end
  end
end
