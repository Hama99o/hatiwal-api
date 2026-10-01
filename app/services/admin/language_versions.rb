# The per-language versions of one admin message — shared by one-to-one
# Messages and bulk, email and in-app (docs/EMAIL.md).
#
#   raw:      { "en" => { "subject" => …, "body" => … }, "ps" => {…}, … }
#   subject:  whether a subject is part of a version (only when emailing —
#             in-app messages have no subject)
#
# A language counts as WRITTEN only when everything it needs is present, so a
# half-filled box can never be sent as if it were complete.
class Admin::LanguageVersions
  LOCALES = User::SUPPORTED_LANGUAGES
  NAMES = { "en" => "English", "ps" => "Pashto", "fa" => "Dari", "ur" => "Urdu" }.freeze

  attr_reader :fallback, :versions

  def initialize(raw, fallback:, subject:)
    @subject = subject
    @fallback = fallback.to_s.presence_in(LOCALES) || "en"
    @versions = LOCALES.each_with_object({}) do |loc, acc|
      entry = (raw || {}).to_h.stringify_keys[loc] || {}
      s = entry["subject"].to_s.strip
      b = entry["body"].to_s.strip
      next if b.blank? || (subject && s.blank?)

      acc[loc] = subject ? { "subject" => s, "body" => b } : { "body" => b }
    end
  end

  def written = versions.keys
  def fallback_written? = versions.key?(fallback)

  # Which version a reader of `preferred` gets: their own, else the fallback.
  def locale_for(preferred)
    versions.key?(preferred.to_s) ? preferred.to_s : fallback
  end

  def for(preferred) = versions[locale_for(preferred)]

  def fallback_error
    return if fallback_written?

    "Write the #{NAMES[fallback]} version#{' (subject and message)' if @subject}: it is the fallback for anyone without their own."
  end
end
