# Stats landing page at /admin — high-level marketplace health.
#
# Inherits the authenticated Admin base (login required, admin layout/nav).
# Administrate handles per-model CRUD; this hand-built page answers
# "how is the marketplace doing?" with counts + growth-over-time charts.
module Admin
  class DashboardController < Admin::ApplicationController
    CLIENT_WINDOW = 30.days

    def index
      @stats = {
        users_total:       User.count,
        users_sellers:     User.where(seller_mode: true).count,
        users_verified:    User.where(verified: true).count,
        users_active:      User.where(status: :active).count,
        listings_total:    Listing.count,
        listings_active:   Listing.active.count,
        listings_sold:     Listing.where(status: :sold).count,
        listings_reserved: Listing.where(status: :reserved).count,
        listings_draft:    Listing.where(status: :draft).count,
        reports_pending:   Report.where(status: :pending).count,
        reports_total:     Report.count,
        categories_total:  Category.count
      }

      # Which app builds are in use (ClientVersionReporting). The number to read
      # before switching on anything an old build can't render — first of all
      # SUPPORT_ADMIN_INITIATE. A user on two devices can appear in both.
      since = CLIENT_WINDOW.ago
      @app_versions = User.reported_version_since(since)
                          .group(:last_app_platform, :last_app_version).count
                          .sort_by { |(platform, version), _| [ platform.to_s, Gem::Version.new(version) ] }.reverse
      @legacy_clients = User.on_legacy_client_since(since).count

      # Growth over the last ~12 weeks (groupdate)
      @users_per_week    = User.group_by_week(:created_at, last: 12).count
      @listings_per_week = Listing.group_by_week(:created_at, last: 12).count

      # Composition
      @listings_by_status = Listing.group(:status).count.transform_keys { |k| Listing.statuses.key(k) || k }
      @reports_by_status  = Report.group(:status).count.transform_keys { |k| Report.statuses.key(k) || k }

      # Top categories by listing count
      @top_categories = Category.left_joins(:listings)
                                .group(:name_en)
                                .order(Arel.sql("COUNT(listings.id) DESC"))
                                .limit(8)
                                .count("listings.id")
    end
  end
end
