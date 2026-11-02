require "rails_helper"

# Prohibited items (owner, 2026-10-13): the admin keeps the term list.
RSpec.describe "Admin prohibited terms", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let!(:term) { create(:prohibited_term, term: "opium", category: :drugs, locale: :en) }

  describe "without an admin session" do
    it "sends a visitor to the admin login and changes nothing" do
      get admin_prohibited_terms_path
      expect(response).to redirect_to(new_admin_user_session_path)
      post admin_prohibited_terms_path, params: { prohibited_term: { term: "x", locale: "en", category: "drugs" } }
      expect(response).to redirect_to(new_admin_user_session_path)
      delete admin_prohibited_term_path(term)
      expect(response).to redirect_to(new_admin_user_session_path)
      expect(ProhibitedTerm.pluck(:term)).to eq([ "opium" ])
    end

    it "does not let a marketplace user in" do
      sign_in create(:user), scope: :user
      get admin_prohibited_terms_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  describe "as an admin" do
    before { sign_in admin, scope: :admin_user }

    it "lists and filters the terms" do
      create(:prohibited_term, term: "شراب", locale: :any, category: :alcohol)
      get admin_prohibited_terms_path
      expect(response.body).to include("opium", "شراب", "nav-prohibited-terms")
      get admin_prohibited_terms_path(category: "alcohol")
      expect(response.body).to include("شراب").and(satisfy { |b| !b.include?("opium") })
    end

    it "shows the form with how matching works" do
      get new_admin_prohibited_term_path
      expect(response.body).to include("prohibited-term-hint", "شیشه")
    end

    it "adds a term, normalized, and logs it" do
      post admin_prohibited_terms_path, params: { prohibited_term: { term: "ترياك*", locale: "fa", category: "drugs", note: "variants" } }
      created = ProhibitedTerm.find_by!(locale: :fa)
      expect(created.term).to eq("تریاک*")
      expect(response).to redirect_to(admin_prohibited_term_path(created))
      expect(AdminAuditLog.find_by(action: "prohibited_term_create")).to have_attributes(target: created, admin_user: admin)
    end

    it "refuses a duplicate with a message" do
      post admin_prohibited_terms_path, params: { prohibited_term: { term: "OPIUM", locale: "en", category: "drugs" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already in the list")
    end

    it "edits a term and logs it" do
      patch admin_prohibited_term_path(term), params: { prohibited_term: { category: "medicine" } }
      expect(term.reload.category).to eq("medicine")
      expect(AdminAuditLog.find_by(action: "prohibited_term_update").details).to include("medicine")
    end

    it "removes a term and logs it" do
      delete admin_prohibited_term_path(term)
      expect(ProhibitedTerm.exists?(term.id)).to be(false)
      expect(AdminAuditLog.find_by(action: "prohibited_term_destroy").details).to include("opium")
    end
  end
end
