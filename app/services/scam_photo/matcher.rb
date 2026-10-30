module ScamPhoto
  # Finds the photos of a live listing that are the SAME photo as a photo of another account's
  # live listing (IDEA-5, 1.2.1; hatiwal-mobile docs/design/SCAM_PHOTO.md §3), and flags the newer
  # listing of each pair for an admin. Never blocks, never changes a listing.
  #
  #   1. CLIP pre-filter: cosine >= MIN_COSINE (today's vectors, compared in Ruby like
  #      ImageSearch::RubyCosineIndex; a pgvector query later answers the same question).
  #   2. Same photo: invariant pHash distance <= Hasher::MATCH_DISTANCE.
  # CLIP alone cannot tell a copy from another photo of a look-alike product; the hash alone would
  # be compared with every photo. Measured: docs/qa-1.2.1/scam-photo/measurement/.
  #
  # Never compared: the same account, the people of a shop the seller belongs to (a team reuses
  # its own photos), listings that are not live or were removed, and pairs an admin dismissed.
  #
  # Every decision is logged as "[scam_photo] ..." with ids and scores only (never a photo).
  class Matcher
    MIN_COSINE = 0.85
    # A photo compared for longer than this logs a warning: time to move to pgvector.
    SLOW_MS = 500

    Pair = Data.define(:attachment_id, :matched_listing_id, :matched_attachment_id, :cosine, :hash_distance)

    def self.call(listing)
      new(listing).call
    end

    def initialize(listing)
      @listing = listing
    end

    # The PhotoMatch rows written or confirmed, one per matched listing.
    def call
      return [] unless ScamPhoto.enabled? && candidate?(@listing)

      photos = rows(ListingImageEmbedding.where(listing_id: @listing.id))
      return [] if photos.empty?

      others = rows(candidates)
      best_pairs(photos, others).filter_map { |pair| record!(pair) }
    end

    private

    def candidate?(listing)
      listing.live? && listing.removed_at.nil?
    end

    # [listing_id, attachment_id, vector, hashes] of today's model, hashed photos only.
    def rows(scope)
      scope.current_model.where.not(photo_hashes: nil)
           .pluck(:listing_id, :attachment_id, :embedding, :photo_hashes)
           .map { |id, attachment_id, bytes, hashes| [ id, attachment_id, ListingImageEmbedding.unpack(bytes), hashes ] }
    end

    def candidates
      listings = Listing.live.not_removed.where.not(id: @listing.id).where.not(user_id: team_user_ids)
      listings = listings.where("listings.shop_id IS DISTINCT FROM ?", @listing.shop_id) if @listing.shop_id
      ListingImageEmbedding.where(listing_id: listings.select(:id))
    end

    # The seller and everyone who shares a shop with them (owner or member).
    def team_user_ids
      user_id = @listing.user_id
      shop_ids = ShopMember.where(user_id: user_id).pluck(:shop_id) | Shop.where(owner_id: user_id).pluck(:id)
      [ user_id ] | ShopMember.where(shop_id: shop_ids).pluck(:user_id) | Shop.where(id: shop_ids).pluck(:owner_id)
    end

    # The best pair per other listing: the closest hash, then the highest cosine.
    def best_pairs(photos, others)
      best = {}
      photos.each do |_listing_id, attachment_id, vector, hashes|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        others.each do |other_listing_id, other_attachment_id, other_vector, other_hashes|
          cosine = dot(vector, other_vector)
          next if cosine < MIN_COSINE

          distance = Hasher.distance(hashes, other_hashes)
          pair = Pair.new(attachment_id, other_listing_id, other_attachment_id, cosine, distance)
          if distance > Hasher::MATCH_DISTANCE
            log(:info, "near", pair)
            next
          end

          current = best[other_listing_id]
          best[other_listing_id] = pair if current.nil? || [ distance, -cosine ] < [ current.hash_distance, -current.cosine ]
        end
        warn_if_slow(attachment_id, others.size, started)
      end
      best.values
    end

    def dot(a, b)
      score = 0.0
      i = 0
      while i < a.size
        score += a[i] * b[i]
        i += 1
      end
      score
    end

    # The newer listing of the pair carries the flag; the older is the likely original.
    def record!(pair)
      other = Listing.find_by(id: pair.matched_listing_id)
      return nil unless other

      newer, older = [ @listing, other ].sort_by { |l| [ l.created_at, l.id ] }.reverse
      own, theirs = newer == @listing ? [ pair.attachment_id, pair.matched_attachment_id ] : [ pair.matched_attachment_id, pair.attachment_id ]

      PhotoMatch.transaction do
        match = PhotoMatch.lock.find_or_initialize_by(listing: newer, matched_listing: older)
        if match.dismissed?
          log(:info, "dismissed", pair, newer: newer, older: older)
          return nil
        end

        flag = Flag.raise_for_reused_photo!(newer)
        match.update!(attachment_id: own, matched_attachment_id: theirs, cosine: pair.cosine,
                      hash_distance: pair.hash_distance, flag: flag, status: :open)
        log(:info, "match", pair, newer: newer, older: older, own: own, theirs: theirs, flag: flag)
        match
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def warn_if_slow(attachment_id, count, started)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      return unless ms > SLOW_MS

      Rails.logger.warn("[scam_photo] slow listing=#{@listing.id} attachment=#{attachment_id} candidates=#{count} ms=#{ms}")
    end

    def log(level, what, pair, newer: @listing, older: nil, own: pair.attachment_id, theirs: pair.matched_attachment_id, flag: nil)
      matched = older ? older.id : pair.matched_listing_id
      line = "[scam_photo] #{what} listing=#{newer.id} matched=#{matched} attachment=#{own} matched_attachment=#{theirs} " \
             "cosine=#{pair.cosine.round(4)} hash=#{pair.hash_distance}"
      line += " flag=#{flag.id}" if flag
      Rails.logger.public_send(level, line)
    end
  end
end
