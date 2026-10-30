# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.1): the ONE link of every share —
#   https://hatiwal.com/l/<id>?lang=ps&src=wa     (a listing)
#   https://hatiwal.com/s/<id>?lang=fa&src=qr     (a shop)
# The short paths are the app-link paths (the app opens when installed, the web otherwise).
# `lang` is the SHARER's language (the web redirect builds the link preview in it); `src` says what
# shared it, counted in our own log (.log_visit). Both are whitelisted: an unknown value is dropped,
# never copied into a link or a log line.
module ShareLink
  LANGS = %w[en ps fa].freeze
  SOURCES = %w[wa share qr].freeze

  module_function

  # nil without PUBLIC_SHARE_BASE_URL (no host is hardcoded; the app then builds its own deep link).
  def for(record, lang: nil, src: nil)
    base = record.class.share_url_for(record)
    return nil if base.nil?

    query = { lang: lang.to_s.presence_in(LANGS), src: src.to_s.presence_in(SOURCES) }.compact
    query.empty? ? base : "#{base}?#{query.to_query}"
  end

  def lang(value) = value.to_s.presence_in(LANGS)

  # One line per visit that came from a share: "[share_visit] src=wa kind=listing id=86 lang=ps".
  def log_visit(kind, id, src:, lang: nil)
    source = src.to_s.presence_in(SOURCES)
    return if source.nil?

    Rails.logger.info("[share_visit] src=#{source} kind=#{kind} id=#{id.to_i} lang=#{lang(lang)}")
  end
end
