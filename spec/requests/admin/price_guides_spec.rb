require "rails_helper"

# IDEA-4: a read-only admin page — every bucket against the threshold, so the
# owner sees which categories are close to switching on.
RSpec.describe "Admin price guides", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:phones) { create(:category, :with_parent, name_en: "Phones & Tablets") }

  it "is admin-only" do
    get admin_price_guides_path
    expect(response).to redirect_to(new_admin_user_session_path)
  end

  it "lists the buckets with their counts against 5 sales / 3 sellers, and is read-only" do
    PriceGuide.create!(category: phones, currency: "AFN", sales_count: 3, sellers_count: 2, available: false, refreshed_at: Time.current)
    sign_in create(:admin_user), scope: :admin_user
    get admin_price_guides_path
    expect(response.body).to include("Phones &amp; Tablets", "AFN", "3 / 5", "2 / 3", "nav-price-guides")
    expect(response.body).not_to include("/admin/price_guides/new")
    expect { Rails.application.routes.recognize_path("/admin/price_guides/1/edit") }.to raise_error(ActionController::RoutingError)
  end
end
