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
        verifications_waiting: VerificationRequest.requested.count,
        # SHOP-1
        shops_total:       Shop.count,
        shops_new_week:    Shop.where(created_at: 1.week.ago..).count,
        shops_verified:    Shop.where.not(verified_at: nil).count,
        shop_verifications_waiting: VerificationRequest.for_shops.requested.count,
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
      # Whether pushes can reach each platform at all — see push_reach_since.
      @push_reach = User.push_reach_since(since)

      # Growth: new users / new listings per week, month or year (?period=),
      # bucketed on Kabul time with Saturday weeks — see Admin::GrowthSeries.
      @growth_period = Admin::GrowthSeries.normalize(params[:period])
      @new_users     = Admin::GrowthSeries.for(User.members, @growth_period)
      # Soft-deleted accounts STAY in the new-user counts: the chart records who
      # signed up when, so a past week must not shrink when someone later leaves.
      # The view labels this and shows how many of the range have since deleted.
      @new_users_since_deleted = Admin::GrowthSeries.for(User.members.where.not(deleted_at: nil), @growth_period).values.sum
      @new_listings  = Admin::GrowthSeries.for(Listing.all, @growth_period)

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
