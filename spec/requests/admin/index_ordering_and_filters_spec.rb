require "rails_helper"

# Covers the two things the admin index screens gained:
#   1. a newest-first default order on EVERY dashboard
#   2. combinable filters on users / listings / reports / warnings
#
# Administrate's own COLLECTION_FILTERS links are untouched and still work; these
# are the separate, combinable bar.
RSpec.describe "Admin index ordering and filters", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, password: "changeme123!") }

  before { sign_in admin, scope: :admin_user }

  # Position of each id in the rendered HTML, so "newest first" is asserted
  # against the actual table rather than against the controller's relation.
  def order_of(body, ids)
    ids.map { |id| body.index("admin/users/#{id}") || body.index(">#{id}<") }
  end

  describe "default ordering" do
    it "lists users newest first without any sort param" do
      old = create(:user, created_at: 10.days.ago, email: "old@example.com")
      new = create(:user, created_at: 1.hour.ago, email: "new@example.com")

      get admin_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index(new.email)).to be < response.body.index(old.email)
    end

    it "still honours an explicit column sort, so headers keep working" do
      old = create(:user, created_at: 10.days.ago, email: "old@example.com")
      new = create(:user, created_at: 1.hour.ago, email: "new@example.com")

      get admin_users_path, params: { user: { order: "created_at", direction: "asc" } }

      expect(response).to have_http_status(:ok)
      expect(response.body.index(old.email)).to be < response.body.index(new.email)
    end

    it "applies to a dashboard that declares no filters of its own" do
      # blocks has COLLECTION_FILTERS = {} and no filter bar; it still inherits
      # the ordering from Admin::ApplicationController.
      get admin_blocks_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "user filters" do
    it "filters by status, reading the values off the enum" do
      banned = create(:user, status: :banned, email: "banned@example.com")
      active = create(:user, status: :active, email: "active@example.com")

      get admin_users_path, params: { status: "banned" }

      expect(response.body).to include(banned.email)
      expect(response.body).not_to include(active.email)
    end

    it "ignores a status the enum does not have instead of raising" do
      create(:user, email: "someone@example.com")

      get admin_users_path, params: { status: "not_a_real_status" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("someone@example.com")
    end

    it "filters by a boolean" do
      yes = create(:user, verified: true, email: "verified@example.com")
      no  = create(:user, verified: false, email: "plain@example.com")

      get admin_users_path, params: { verified: "yes" }

      expect(response.body).to include(yes.email)
      expect(response.body).not_to include(no.email)
    end

    it "combines two filters, which COLLECTION_FILTERS links cannot do" do
      both = create(:user, status: :banned, verified: true, email: "both@example.com")
      one  = create(:user, status: :banned, verified: false, email: "one@example.com")

      get admin_users_path, params: { status: "banned", verified: "yes" }

      expect(response.body).to include(both.email)
      expect(response.body).not_to include(one.email)
    end

    it "filters by a created_at range" do
      inside  = create(:user, created_at: 3.days.ago, email: "inside@example.com")
      outside = create(:user, created_at: 30.days.ago, email: "outside@example.com")

      get admin_users_path, params: {
        created_from: 7.days.ago.to_date.to_s, created_to: Date.current.to_s
      }

      expect(response.body).to include(inside.email)
      expect(response.body).not_to include(outside.email)
    end

    it "ignores an unparseable date rather than raising" do
      create(:user, email: "someone@example.com")

      get admin_users_path, params: { created_from: "not-a-date" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("someone@example.com")
    end

    it "filters by the confirmed scope" do
      confirmed   = create(:user, confirmed_at: Time.current, email: "yes@example.com")
      unconfirmed = create(:user, confirmed_at: nil, email: "no@example.com")

      get admin_users_path, params: { confirmed: "no" }

      expect(response.body).to include(unconfirmed.email)
      expect(response.body).not_to include(confirmed.email)
    end
  end

  describe "listing filters" do
    it "filters by a price range" do
      cheap = create(:listing, price: 100, title: "Cheap Thing")
      dear  = create(:listing, price: 90_000, title: "Dear Thing")

      get admin_listings_path, params: { price_min: "1000" }

      expect(response.body).to include(dear.title)
      expect(response.body).not_to include(cheap.title)
    end

    it "filters by status" do
      sold = create(:listing, status: :sold, title: "Sold Thing")
      live = create(:listing, status: :active, title: "Live Thing")

      get admin_listings_path, params: { status: "sold" }

      expect(response.body).to include(sold.title)
      expect(response.body).not_to include(live.title)
    end

    # Listings attach to SUBcategories, so a parent pick must reach its children.
    it "includes a parent category's subcategory listings" do
      parent = create(:category)
      child  = create(:category, parent: parent)
      other  = create(:category)
      in_child = create(:listing, category: child, title: "Child Phone")
      elsewhere = create(:listing, category: other, title: "Other Thing")

      get admin_listings_path, params: { category: parent.id }

      expect(response.body).to include(in_child.title)
      expect(response.body).not_to include(elsewhere.title)
    end

    # expires_at is nullable; NULL never matches a range comparison.
    it "counts a listing with no expiry as not expired" do
      no_expiry = create(:listing, :active, title: "Forever Thing")
      no_expiry.update_column(:expires_at, nil)
      lapsed = create(:listing, :expired, title: "Lapsed Thing")

      get admin_listings_path, params: { expired: "no" }

      expect(response.body).to include(no_expiry.title)
      expect(response.body).not_to include(lapsed.title)
    end

    it "treats a typed % in a text filter literally, not as match-all" do
      create(:listing, location: "Kabul", title: "Kabul Thing")

      get admin_listings_path, params: { location: "%" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Kabul Thing")
    end
  end

  describe "deleted users filter" do
    it "separates soft-deleted users from live ones" do
      gone = create(:user, deleted_at: 1.day.ago, email: "gone@example.com")
      here = create(:user, email: "here@example.com")

      get admin_users_path, params: { deleted: "no" }

      expect(response.body).to include(here.email)
      expect(response.body).not_to include(gone.email)
    end
  end

  describe "the filter bar itself" do
    # Assert on the element id, NOT a class name: the admin stylesheet lives in
    # _theme.html.erb and is rendered on every page, so every `.filter-bar*`
    # class name appears in the body whether the bar rendered or not. That is
    # what made the first version of these two examples pass vacuously.
    it "renders on a dashboard that declares filters" do
      get admin_users_path
      expect(response.body).to include('id="admin-filter-bar"')
    end

    it "does not render on a dashboard that declares none" do
      get admin_blocks_path
      expect(response.body).not_to include('id="admin-filter-bar"')
    end

    it "offers a Clear link only once a filter is applied" do
      get admin_users_path
      expect(response.body).not_to include(">Clear</a>")

      get admin_users_path, params: { verified: "yes" }
      expect(response.body).to include(">Clear</a>")
    end
  end
end
