require "rails_helper"

# Security (d0, 2026-10-08): POST /reports took `reportable_type` from the
# client and Rails constantized it to load the target, so any class name in
# the app could be named (and an unknown one raised a 500). Only Listing and
# User can be reported; anything else is refused BEFORE it is constantized.
RSpec.describe "Reports — reportable_type allowlist", type: :request do
  let(:reporter) { create(:user) }

  def report(type, id = 1)
    post "/api/v1/reports", params: { report: { reportable_type: type, reportable_id: id, reason: "fraud" } },
                            headers: auth_headers_for(reporter)
  end

  it "refuses any other class name with a coded 422, without constantizing it" do
    reporter
    %w[Kernel AdminUser User::Something NoSuchThing Report ActiveRecord::Base].each do |type|
      report(type)
      expect(response).to have_http_status(:unprocessable_entity), "#{type} → #{response.status}"
      expect(JSON.parse(response.body)["code"]).to eq("unknown_reportable_type")
    end
    expect(Report.count).to eq(0)
  end

  it "still reports a listing and a user" do
    report("Listing", create(:listing, :active).id)
    expect(response).to have_http_status(:created)
    report("User", create(:user).id)
    expect(response).to have_http_status(:created)
  end
end
