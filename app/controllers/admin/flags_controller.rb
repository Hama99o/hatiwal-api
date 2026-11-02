# "Flagged listings" (prohibited items, owner 2026-10-13, option B: ALL MANUAL).
# The open flags first: what was matched or reported, and three decisions,
# each confirmed and written to the audit log: Dismiss, Take down, Take down +
# warning. The decisions live in ProhibitedItems::Moderation; this only
# orchestrates.
#
# Hand-built like VerificationRequestsController: a decision queue, not a CRUD
# table.
module Admin
  class FlagsController < Admin::ApplicationController
    include Pundit::Authorization

    PER_PAGE = 25
    STATUSES = %w[open dismissed actioned all].freeze
    KINDS = { "listings" => Listing.name, "shops" => Shop.name }.freeze

    before_action :set_flag, only: %i[show dismiss take_down take_down_warn]

    rescue_from Pundit::NotAuthorizedError do
      redirect_to admin_flags_path, alert: "Not allowed: this flag was already decided."
    end

    def index
      authorize [ :admin, Flag ]
      flags = policy_scope([ :admin, Flag ])
      @status = params[:status].presence_in(STATUSES) || "open"
      @kind = params[:kind].presence_in(KINDS.keys)
      flags = flags.where(flaggable_type: KINDS[@kind]) if @kind
      @counts = STATUSES.index_with { |s| s == "all" ? flags.count : flags.where(status: s).count }
      flags = flags.where(status: @status) unless @status == "all"
      # Open: oldest first (first come, first served). Decided: newest first.
      flags = @status == "open" ? flags.order(:created_at, :id) : flags.order(Arel.sql("COALESCE(acted_at, created_at) DESC"), id: :desc)
      @flags = flags.includes(:flaggable, :acted_by).page(params[:page]).per(PER_PAGE)
      @report_counts = report_counts(@flags)
    end

    def show
      @reports = @flag.reports.includes(:reporter).order(:created_at)
      @audit = AdminAuditLog.where(target: @flag.flaggable).recent.includes(:admin_user).limit(20) if @flag.flaggable
    end

    def dismiss
      decide("flag_dismiss") { moderation.dismiss! }
    end

    def take_down
      decide("flag_take_down") { moderation.take_down! }
    end

    def take_down_warn
      decide("flag_take_down_warn") { moderation.take_down!(warn: true) }
    end

    private

    def set_flag
      @flag = policy_scope([ :admin, Flag ]).find(params[:id])
      authorize [ :admin, @flag ]
    end

    def pundit_user
      current_admin_user
    end

    def moderation
      @moderation ||= ProhibitedItems::Moderation.new(@flag, admin: current_admin_user, note: params[:note], category: params[:category])
    end

    def decide(action)
      yield
      log_admin_action(action, target: @flag.flaggable,
                               details: [ "flag ##{@flag.id}", @flag.category, @flag.note ].compact.join(" · "))
      redirect_to admin_flags_path, notice: notice_for(action)
    rescue ProhibitedItems::Moderation::Refused, ActiveRecord::RecordInvalid => e
      redirect_to admin_flag_path(@flag), alert: e.message
    end

    def notice_for(action)
      what = @flag.listing? ? "Listing" : "Shop"
      case action
      when "flag_dismiss" then "Flag dismissed. Nothing was said to the seller."
      when "flag_take_down" then "#{what} taken down. The seller was told why in Support."
      else "#{what} taken down and a warning issued. The seller was told why in Support."
      end
    end

    # Prohibited-item report count per listing on this page, in one query.
    def report_counts(flags)
      ids = flags.select(&:listing?).map(&:flaggable_id)
      return {} if ids.empty?

      Report.where(reportable_type: Listing.name, reportable_id: ids, reason: :prohibited_item).group(:reportable_id).count
    end
  end
end
