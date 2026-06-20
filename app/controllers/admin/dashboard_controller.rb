# Stats landing page at /admin — high-level marketplace health.
#
# Inherits the authenticated Admin base (login required, admin layout/nav).
# Administrate handles per-model CRUD; this hand-built page answers
# "how is the marketplace doing?" with counts + growth-over-time charts.
module Admin
  class DashboardController < Admin::ApplicationController
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
