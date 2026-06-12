require "rails_helper"

RSpec.describe "Api::V1::Reports", type: :request do
  let(:reporter) { create(:user) }
  let(:headers)  { auth_headers_for(reporter) }
  let(:listing)  { create(:listing) }

  describe "POST /api/v1/reports" do
    let(:valid_params) do
      {
        report: {
          reportable_type: "Listing",
          reportable_id:   listing.id,
          reason:          "spam",
          description:     "Looks like a scam"
        }
      }
    end

    it "requires authentication" do
      post "/api/v1/reports", params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a report and returns 201" do
      expect do
        post "/api/v1/reports", params: valid_params, headers: headers, as: :json
      end.to change(Report, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]).to eq("Report submitted")
    end

    it "assigns the current user as reporter" do
      post "/api/v1/reports", params: valid_params, headers: headers, as: :json
      expect(Report.last.reporter).to eq(reporter)
    end

    it "rejects reporting your own listing" do
      own = create(:listing, user: reporter)
      params = valid_params.deep_merge(report: { reportable_id: own.id })

      post "/api/v1/reports", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    it "rejects a report with no reason" do
      params = { report: { reportable_type: "Listing", reportable_id: listing.id } }

      expect do
        post "/api/v1/reports", params: params, headers: headers, as: :json
      end.not_to change(Report, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
