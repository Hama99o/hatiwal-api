# A word or phrase that makes a listing or shop worth a look (owner, 2026-10-13,
# option B: ALL MANUAL). A match never blocks anything: it opens a Flag for an
# admin. Kept on the admin page "Prohibited terms"; the starting list is
# config/prohibited_terms.yml.
#
# `term` is stored normalized (ProhibitedItems::Normalizer.term), so what the
# admin sees is exactly what is compared. A trailing "*" = "words starting with".
class ProhibitedTerm < ApplicationRecord
  SEED_FILE = Rails.root.join("config/prohibited_terms.yml")

  # Owner list, 2026-10-13. `medicine` is review-worthy, not forbidden; `other`
  # is for a report-only flag an admin files under none of these.
  CATEGORIES = {
    firearms: 0, ammunition: 1, explosives: 2, drugs: 3, alcohol: 4,
    fake_documents: 5, stolen_goods: 6, adult: 7, gambling: 8,
    human_trafficking: 9, medicine: 10, other: 11
  }.freeze

  enum :locale, { en: 0, ps: 1, fa: 2, any: 3 }, prefix: :locale
  enum :category, CATEGORIES, prefix: :category

  has_many :flags, dependent: :nullify

  before_validation :normalize_term

  validates :term, presence: true, length: { maximum: 100 },
                   uniqueness: { scope: :locale, message: "is already in the list for this language" }
  validates :locale, :category, presence: true

  scope :ordered, -> { order(:category, :locale, :term) }

  # Adds every term of the starting list that is missing; never edits or
  # deletes a row. Safe to run again (and in production); a term an admin
  # deleted comes back only if this is run again by hand (the data migration
  # runs once). Returns the number of rows inserted.
  def self.seed_defaults!(file = SEED_FILE)
    now = Time.current
    rows = YAML.load_file(file).flat_map do |category, by_locale|
      by_locale.flat_map do |locale, terms|
        Array(terms).map do |raw|
          { term: ProhibitedItems::Normalizer.term(raw), locale: locales.fetch(locale.to_s),
            category: categories.fetch(category.to_s), created_at: now, updated_at: now }
        end
      end
    end
    rows = rows.reject { |r| r[:term].blank? }.uniq { |r| r.values_at(:term, :locale) }
    rows.empty? ? 0 : insert_all(rows, unique_by: %i[term locale]).length
  end

  def to_s
    term
  end

  private

  def normalize_term
    self.term = ProhibitedItems::Normalizer.term(term)
  end
end
