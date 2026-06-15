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

    it "creates a report and returns 201 via render_ok (not bare render json:)" do
      expect do
        post "/api/v1/reports", params: valid_params, headers: headers, as: :json
      end.to change(Report, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]).to eq("Report submitted")
    end

    it "controller source contains no bare render json: literal" do
      controller_source = File.read(
        Rails.root.join("app/controllers/api/v1/reports_controller.rb")
      )
      expect(controller_source).not_to include("render json:")
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

    it "rejects a description longer than 1000 characters and returns 422" do
      params = valid_params.deep_merge(
        report: { description: "x" * 1001 }
      )

      expect do
        post "/api/v1/reports", params: params, headers: headers, as: :json
      end.not_to change(Report, :count)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end

    it "accepts a description at the 1000-character boundary" do
      params = valid_params.deep_merge(
        report: { description: "y" * 1000 }
      )

      expect do
        post "/api/v1/reports", params: params, headers: headers, as: :json
      end.to change(Report, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "accepts a report with a blank description" do
      params = valid_params.deep_merge(report: { description: "" })

      expect do
        post "/api/v1/reports", params: params, headers: headers, as: :json
      end.to change(Report, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "returns 422 (not 500) when the same reporter submits a duplicate report for the same listing" do
      # First report succeeds
      post "/api/v1/reports", params: valid_params, headers: headers, as: :json
      expect(response).to have_http_status(:created)

      # Second identical report must return 422, not 500
      expect do
        post "/api/v1/reports", params: valid_params, headers: headers, as: :json
      end.not_to change(Report, :count)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end

    it "returns 422 (not 500) when the same reporter submits a duplicate report for the same user" do
      other_user = create(:user)
      user_params = {
        report: {
          reportable_type: "User",
          reportable_id:   other_user.id,
          reason:          "spam"
        }
      }

      # First report succeeds
      post "/api/v1/reports", params: user_params, headers: headers, as: :json
      expect(response).to have_http_status(:created)

      # Duplicate must return 422
      expect do
        post "/api/v1/reports", params: user_params, headers: headers, as: :json
      end.not_to change(Report, :count)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end
  end
end
