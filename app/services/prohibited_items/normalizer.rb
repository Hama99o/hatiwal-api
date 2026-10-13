# Prohibited items (owner, 2026-10-13, option B: ALL MANUAL). One spelling for
# the text a seller typed and for the terms an admin keeps, so that "تریاک",
# "ترياك" and "تَریاک" are the same word, and "AK-47" is "ak 47".
#
# In order:
#   1. NFKC: Arabic presentation forms (ﻻ, ﺗ…) become plain letters, full-width
#      Latin becomes ASCII.
#   2. Strip what is invisible or decorative: harakat / Quranic marks, tatweel,
#      ZWNJ / ZWJ and bidi marks. ZWNJ is REMOVED, not turned into a space, so
#      "شرط‌بندی" reads "شرطبندی" (the seed carries both spellings).
#   3. One letter for each letter: Arabic ي/ى → Persian ی, ك → ک, ة → ه,
#      أ/إ/آ/ٱ → ا, ؤ → و, ۀ → ه.
#   4. Persian and Arabic-Indic digits → ASCII.
#   5. downcase; every run of anything that is not a letter or a digit becomes
#      ONE space (so punctuation never glues or splits a word).
#
# A trailing "*" on a TERM (an admin's "starts with" marker) survives #term.
module ProhibitedItems::Normalizer
  # Harakat and Quranic annotation marks; U+0670 is the superscript alef.
  MARKS = /[ؐ-ًؚ-ٰٟۖ-ۜ۟-۪ۨ-ۭ]/
  # Tatweel, ZWNJ, ZWJ, LRM/RLM, bidi embeddings and isolates, BOM.
  INVISIBLE = /[ـ​-‏‪-‮⁦-⁩﻿]/
  LETTERS = {
    "ي" => "ی", "ى" => "ی", "ك" => "ک", "ة" => "ه", "ۀ" => "ه",
    "أ" => "ا", "إ" => "ا", "آ" => "ا", "ٱ" => "ا", "ؤ" => "و"
  }.freeze
  LETTER_PATTERN = Regexp.union(LETTERS.keys)
  PERSIAN_DIGITS = "۰۱۲۳۴۵۶۷۸۹".freeze
  ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩".freeze
  NOT_WORD = /[^\p{L}\p{N}]+/

  module_function

  # Running text → space-separated tokens, e.g. " د پخلنځي چاقو ".
  def text(value)
    base(value).gsub(NOT_WORD, " ").strip
  end

  # A term as stored: normalized like text, plus the optional trailing "*".
  def term(value)
    raw = value.to_s.strip
    prefix = raw.end_with?("*")
    normalized = text(raw.delete_suffix("*"))
    prefix && normalized.present? ? "#{normalized}*" : normalized
  end

  def base(value)
    value.to_s
         .unicode_normalize(:nfkc)
         .gsub(MARKS, "")
         .gsub(INVISIBLE, "")
         .gsub(LETTER_PATTERN, LETTERS)
         .tr(PERSIAN_DIGITS, "0123456789")
         .tr(ARABIC_DIGITS, "0123456789")
         .downcase
  end
end
