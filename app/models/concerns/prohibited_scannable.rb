# Prohibited items (owner, 2026-10-13, option B: ALL MANUAL): after a listing or
# a shop is saved with new public text, look for prohibited terms and open a
# Flag for an admin when one is found. NOTHING about the record changes, and a
# failure here never fails the save (it is reported, not raised).
#
# The including model says WHEN to scan (#prohibited_scan_due?) and WHAT text
# (#prohibited_scan_texts).
module ProhibitedScannable
  extend ActiveSupport::Concern

  included do
    has_many :flags, as: :flaggable, dependent: :destroy

    after_commit :scan_for_prohibited_terms, on: %i[create update], if: :prohibited_scan_due?
  end

  def scan_for_prohibited_terms
    Flag.raise_for_terms!(self, ProhibitedItems::Matcher.current.matches(*prohibited_scan_texts))
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { flaggable: "#{self.class.name}##{id}" })
    nil
  end
end
