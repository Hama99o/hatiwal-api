require "rails_helper"

# Prohibited items (owner, 2026-10-13): the "Flagged listings" queue and its
# three decisions.
RSpec.describe "Admin flagged listings", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user) }
  let(:seller) { create(:user, firstname: "Gul", preferred_language: "ps") }
  let(:listing) { create(:listing, :active, user: seller, title: "Kalashnikov") }
  let!(:flag) { create(:flag, flaggable: listing, category: :firearms, matched_term: "kalashnikov") }

  describe "without an admin session" do
    it "sends a visitor to the admin login, for every page and action" do
      get admin_flags_path
      expect(response).to redirect_to(new_admin_user_session_path)
      get admin_flag_path(flag)
      expect(response).to redirect_to(new_admin_user_session_path)
      %i[dismiss take_down take_down_warn].each do |action|
        patch send(:"#{action}_admin_flag_path", flag)
        expect(response).to redirect_to(new_admin_user_session_path)
      end
      expect(flag.reload).to be_open
      expect(listing.reload).to be_active
    end

    it "does not let a marketplace user in" do
      sign_in seller, scope: :user
      patch take_down_admin_flag_path(flag)
      expect(response).to redirect_to(new_admin_user_session_path)
      expect(flag.reload).to be_open
    end
  end

  describe "as an admin" do
    before { sign_in admin, scope: :admin_user }

    it "lists open flags with the link, term, category, source and report count, and a red badge" do
      create(:report, :prohibited_item, reportable: listing)
      shop_flag = create(:flag, :on_shop, :from_report)
      create(:flag, :dismissed, matched_term: "gone")

      get admin_flags_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Kalashnikov", admin_listing_path(listing), "kalashnikov", "Firearms", "Term", admin_shop_path(shop_flag.flaggable))
      expect(body).to include('nav-badge nav-badge--danger', ">2</span>")
      expect(body).not_to include("gone")
      row = body[/<tr id="flag-row-#{flag.id}">.*?<\/tr>/m]
      expect(row).to include("<td>1</td>")
    end

    it "filters by status and kind" do
      create(:flag, :dismissed, matched_term: "oldmatch")
      get admin_flags_path(status: "dismissed")
      expect(response.body).to include("oldmatch").and(satisfy { |b| !b.include?("Kalashnikov") })
      get admin_flags_path(kind: "shops")
      expect(response.body).to include("No open flags")
    end

    it "shows one flag with its decisions" do
      get admin_flag_path(flag)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("flag-take-down-warn", "flag-take-down", "flag-dismiss", "data-confirm")
    end

    it "dismisses: closes the flag, logs it, says nothing to the seller" do
      expect { patch dismiss_admin_flag_path(flag), params: { note: "a toy" } }.not_to have_enqueued_job(SupportNoticeJob)
      expect(response).to redirect_to(admin_flags_path)
      expect(flag.reload).to have_attributes(status: "dismissed", note: "a toy", acted_by: admin)
      expect(AdminAuditLog.find_by(action: "flag_dismiss")).to have_attributes(target: listing, admin_user: admin)
      expect(listing.reload).to be_active
    end

    it "takes down: listing to draft, Support message to the seller, audit log" do
      expect { patch take_down_admin_flag_path(flag), params: { category: "firearms", note: "no weapons" } }
        .to have_enqueued_job(SupportNoticeJob).with(seller.id, "listing_prohibited_removed", nil, hash_including("category" => "firearms", "note" => "no weapons"))
      expect(listing.reload).to be_draft
      expect(flag.reload).to have_attributes(status: "actioned", action_taken: "take_down")
      expect(AdminAuditLog.find_by(action: "flag_take_down").details).to include("flag ##{flag.id}", "firearms", "no weapons")
      expect(seller.reload.warnings).to be_empty
    end

    it "takes down + warns: one strike, even on a double click" do
      2.times { patch take_down_warn_admin_flag_path(flag) }
      expect(seller.reload.warnings.count).to eq(1)
      expect(flag.reload.action_taken).to eq("take_down_warn")
      expect(AdminAuditLog.where(action: "flag_take_down_warn").count).to eq(1)
      expect(flash[:alert]).to include("already decided")
    end

    it "takes a shop down through its suspension" do
      shop_flag = create(:flag, :on_shop, category: :drugs)
      patch take_down_admin_flag_path(shop_flag)
      expect(shop_flag.flaggable.reload).to be_suspended
      expect(AdminAuditLog.find_by(action: "flag_take_down").target).to eq(shop_flag.flaggable)
    end

    it "explains a refusal instead of failing" do
      shop_flag = create(:flag, :on_shop)
      shop_flag.flaggable.update_columns(status: Shop.statuses[:closed])
      patch take_down_admin_flag_path(shop_flag)
      expect(response).to redirect_to(admin_flag_path(shop_flag))
      expect(flash[:alert]).to include("closed")
    end
  end

  # The owner's "Take down" answered 422 in production (2026-10-16): the one form posts
  # to three actions through formaction, and a per-form CSRF token only fits the form's
  # own URL (dismiss). test.rb turns forgery protection off, so turn it on here.
  describe "deciding through the real form, with CSRF protection on" do
    before { sign_in admin, scope: :admin_user }

    around do |example|
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    def form_token
      get admin_flag_path(flag)
      form = response.body[%r{<form[^>]*id="flag-decision".*?</form>}m]
      expect(form).to include(%(formaction="#{take_down_admin_flag_path(flag)}"))
      form[/name="authenticity_token" value="([^"]+)"/, 1]
    end

    it "Take down works with the token the form carries" do
      token = form_token
      patch take_down_admin_flag_path(flag), params: { authenticity_token: token, category: "firearms" }
      expect(response).to have_http_status(:redirect)
      expect(listing.reload).to be_draft
    end

    it "Take down + warning works with the same token" do
      token = form_token
      patch take_down_warn_admin_flag_path(flag), params: { authenticity_token: token, category: "firearms" }
      expect(response).to have_http_status(:redirect)
      expect(listing.reload).to be_draft
    end

    it "Dismiss still works with the same token" do
      token = form_token
      patch dismiss_admin_flag_path(flag), params: { authenticity_token: token, category: "other" }
      expect(flag.reload.status).to eq("dismissed")
    end
  end
end
