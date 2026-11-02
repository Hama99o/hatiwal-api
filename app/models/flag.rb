# "An admin should look at this" (owner, 2026-10-13, option B: ALL MANUAL).
#
# Opened on a listing or a shop by
#   * a prohibited term in its text (source: term), see ProhibitedScannable, or
#   * a "prohibited item" report (source: report), see Report.
# Opening a flag NEVER blocks or changes the listing. The one automatic step is
# Report's: 3 distinct reporters move a live listing to draft (#auto_draft!).
#
# One OPEN flag per listing / shop (partial unique index): a second match or
# report joins the open one. An admin closes it from "Flagged listings":
# dismissed, or actioned (taken down, with or without a warning), see
# ProhibitedItems::Moderation.
class Flag < ApplicationRecord
  # Distinct reporters of "prohibited item" that move a live listing to draft.
  AUTO_DRAFT_REPORTERS = 3
  # Matched terms kept on the flag (the admin list shows them).
  MAX_TERMS = 5
  FLAGGABLE_TYPES = [ Listing.name, Shop.name ].freeze

  belongs_to :flaggable, polymorphic: true
  belongs_to :prohibited_term, optional: true
  belongs_to :acted_by, class_name: AdminUser.name, optional: true

  enum :source, { term: 0, report: 1 }, prefix: :source
  enum :status, { open: 0, dismissed: 1, actioned: 2 }
  enum :category, ProhibitedTerm::CATEGORIES, prefix: :category

  validates :flaggable_type, inclusion: { in: FLAGGABLE_TYPES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  after_create_commit :email_admins

  # ── Opening ────────────────────────────────────────────────────────────────

  # `matches`: ProhibitedItems::Matcher::Match list for `flaggable`'s text.
  # Returns the open flag (new or joined), or nil when nothing is to be done.
  def self.raise_for_terms!(flaggable, matches)
    return nil if matches.blank?

    primary = matches.find { |m| m.category != "medicine" } || matches.first
    terms = matches.map(&:term).uniq.first(MAX_TERMS).join(", ")
    # An admin already dismissed exactly this: an edit of the same text must
    # not bring it back. A report still can.
    return nil if where(flaggable: flaggable, status: :dismissed, matched_term: terms).exists?

    open_for!(flaggable, source: :term, category: primary.category, matched_term: terms, prohibited_term_id: primary.term_id) do |flag|
      flag.update!(matched_term: terms, prohibited_term_id: primary.term_id, category: flag.category || primary.category) if flag.matched_term.blank?
    end
  end

  # A "prohibited item" report on a listing. Joins / opens the flag, then
  # moves the listing to draft once AUTO_DRAFT_REPORTERS people reported it.
  def self.raise_for_report!(report)
    listing = report.reportable
    return nil unless report.prohibited_item? && listing.is_a?(Listing)

    flag = open_for!(listing, source: :report)
    flag.auto_draft! if flag.distinct_reporters >= AUTO_DRAFT_REPORTERS
    flag
  end

  # The open flag of `flaggable`, created with `attrs` when there is none. A
  # block runs on an EXISTING open flag (to merge what the new signal knows).
  def self.open_for!(flaggable, **attrs)
    existing = open.find_by(flaggable: flaggable)
    if existing
      yield existing if block_given?
      return existing
    end

    create!(flaggable: flaggable, status: :open, **attrs)
  rescue ActiveRecord::RecordNotUnique
    open.find_by!(flaggable: flaggable)
  end

  # ── Reading ────────────────────────────────────────────────────────────────

  # The "prohibited item" reports behind this flag (listings only: shops cannot
  # be reported).
  def reports
    return Report.none unless flaggable_type == Listing.name

    Report.where(reportable_type: Listing.name, reportable_id: flaggable_id, reason: :prohibited_item)
  end

  def distinct_reporters
    reports.distinct.count(:reporter_id)
  end

  def listing? = flaggable_type == Listing.name
  def shop? = flaggable_type == Shop.name

  # Who is answerable for the flagged thing: the listing's seller or the shop's owner.
  def responsible_user
    listing? ? flaggable&.user : flaggable&.owner
  end

  def flaggable_label
    return "(deleted)" unless flaggable

    listing? ? flaggable.title : flaggable.name
  end

  # ── The automatic step ─────────────────────────────────────────────────────

  # 3 distinct "prohibited item" reporters: a LIVE listing goes to draft, the
  # seller is told why (Support), it is written to the audit log. The flag stays
  # open: an admin still decides.
  def auto_draft!
    listing = flaggable
    return false unless listing.is_a?(Listing) && listing.move_to_draft_for_moderation!

    AdminAuditLog.record!(admin_user: nil, action: "auto_draft_listing", target: listing,
                          details: "#{distinct_reporters} prohibited-item reports (flag ##{id})")
    SupportNoticeJob.enqueue_prohibited(listing, :listing_prohibited_auto_drafted)
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.error.report(e, handled: true, context: { flag_id: id, listing_id: listing&.id })
    false
  end

  private

  # FLAG_EMAILS_ENABLED (config.x.flag_emails_enabled): every unlocked admin
  # account gets one email per NEW flag.
  def email_admins
    return unless Rails.application.config.x.flag_emails_enabled

    AdminUser.where(locked_at: nil).find_each do |admin|
      AdminFlagMailer.new_flag(self, admin).deliver_later
    end
  end
end
