# Finds the prohibited terms in a piece of text. Both sides go through
# ProhibitedItems::Normalizer, so the comparison is token against token:
#
#   * a term matches whole words only: "gun" never matches "gunny", and "چرس"
#     never matches inside a longer word. A term of several words matches those
#     words next to each other ("fake passport", "تذکره جعلی").
#   * a Latin term also matches its plain plural ("pistol" → "pistols",
#     "grenade" → "grenades"). Pashto / Dari plurals are added as their own terms.
#   * a term ending in "*" matches any word that STARTS with it ("هیروئین*"
#     also catches "هیروئینو"). The admin form explains it.
#   * a negated mention does not count: "not stolen", "no alcohol", "ضد دزدی"
#     (anti-theft), "دزدی نیست", "غلا نه ده". Sellers write these to reassure
#     buyers; flagging them would bury the real cases.
#
# A match never blocks anything (owner, option B): the caller only opens a Flag.
class ProhibitedItems::Matcher
  Match = Struct.new(:term_id, :term, :category, keyword_init: true)

  LATIN_WORD_END = /[a-z]\z/
  # The word right BEFORE the match that negates it.
  NEGATE_BEFORE = %w[not no non never without anti ضد بدون بی].freeze
  # The word right AFTER the match that negates it (fa نیست / نمیباشد, ps نه).
  NEGATE_AFTER = %w[نیست نمیباشد نمی نه free].freeze

  # The matcher for the current term list, rebuilt only when the list changed
  # (one cheap query per call: count + newest update).
  def self.current
    version = ProhibitedTerm.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    cached = @current
    return cached if cached && cached.version == version

    @current = new(ProhibitedTerm.order(:id).pluck(:id, :term, :category), version: version)
  end

  attr_reader :version

  # rows: [[id, term, category], ...] with `term` already normalized.
  def initialize(rows, version: nil)
    @version = version
    @patterns = rows.filter_map do |id, term, category|
      pattern = self.class.pattern_for(term)
      pattern && [ Match.new(term_id: id, term: term, category: category.to_s), pattern ]
    end
  end

  # Every distinct term found in `texts` (strings, nils allowed), in term order.
  def matches(*texts)
    haystack = texts.flatten.compact.map { |t| ProhibitedItems::Normalizer.text(t) }.join(" | ")
    return [] if haystack.blank?

    @patterns.filter_map { |match, pattern| match if affirmed?(haystack, pattern) }
  end

  def self.pattern_for(term)
    term = term.to_s
    prefix = term.end_with?("*")
    stem = term.delete_suffix("*").strip
    return nil if stem.empty?

    body = Regexp.escape(stem).gsub("\\ ", " ")
    tail =
      if prefix then "\\p{L}*"
      elsif stem.match?(LATIN_WORD_END) then "(?:s|es)?"
      else ""
      end
    Regexp.new("(?<![\\p{L}\\p{N}])#{body}#{tail}(?![\\p{L}\\p{N}])")
  end

  private

  # At least one occurrence that is not negated by the word next to it.
  def affirmed?(haystack, pattern)
    position = 0
    while (found = pattern.match(haystack, position))
      return true unless negated?(found)

      position = [ found.end(0), found.begin(0) + 1 ].max
    end
    false
  end

  def negated?(found)
    NEGATE_BEFORE.include?(found.pre_match.split(" ").last) ||
      NEGATE_AFTER.include?(found.post_match.split(" ").first)
  end
end
