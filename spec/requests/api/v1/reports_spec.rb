require "swagger_helper"

RSpec.describe "Api::V1::Reports", type: :request do
  let(:reporter) { create(:user) }
  let(:headers)  { auth_headers_for(reporter) }
  let(:listing)  { create(:listing) }

  # ── GET /api/v1/reports ──────────────────────────────────────────────────────

  path "/api/v1/reports" do
    get "list the current user's reports" do
      tags "Reports"
      description "Returns a paginated list of reports submitted by the authenticated user. Includes status, reason, and a safe reportable_label."
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end

      response "200", "returns only the current user's reports with pagination" do
        let(:other_user)     { create(:user) }
        let(:other_listing)  { create(:listing) }
        let(:second_listing) { create(:listing) }

        before do
          # Two reports from reporter — different reportables to satisfy uniqueness
          create(:report, reporter: reporter, reportable: listing,        reason: :spam,  status: :pending)
          create(:report, reporter: reporter, reportable: second_listing, reason: :fraud, status: :resolved,
                 description: "Detailed description")
          # One report from another user — must NOT appear in response
          create(:report, reporter: other_user, reportable: other_listing, reason: :spam)
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          reports = data["reports"]
          expect(reports).to be_an(Array)
          # Only reporter's two reports
          expect(reports.length).to eq(2)
          # All belong to the reporter
          reporter_ids = reports.map { |r| r["id"] }
          expect(Report.where(id: reporter_ids).pluck(:reporter_id).uniq).to eq([ reporter.id ])
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "200", "each report has status, reason, and reportable_label" do
        before do
          create(:report, reporter: reporter, reportable: listing, reason: :spam, status: :reviewed)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          report = data["reports"].first
          expect(report).to have_key("status")
          expect(report).to have_key("reason")
          expect(report).to have_key("reportable_label")
          expect(report["reportable_label"]).to eq(listing.title)
        end
      end

      response "200", "reportable_label falls back to '[deleted]' when reportable user was deleted" do
        let(:deletable_user) { create(:user) }

        before do
          # Report against a user; when that user is destroyed the report's reportable
          # becomes nil (User model does NOT cascade-destroy these reports).
          create(:report, :against_user, reporter: reporter, reportable: deletable_user, reason: :spam)
          deletable_user.destroy!
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)
          expect(data["reports"].first["reportable_label"]).to eq("[deleted]")
        end
      end

      response "200", "pagination meta is present" do
        before do
          3.times { create(:report, reporter: reporter, reportable: create(:listing)) }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["meta"]["pagination"]).to have_key("total_count")
          expect(data["meta"]["pagination"]).to have_key("total_pages")
          expect(data["meta"]["pagination"]).to have_key("current_page")
        end
      end
    end

    # ── POST /api/v1/reports ─────────────────────────────────────────────────

    post "submit a report" do
      tags "Reports"
      description "Submits a polymorphic report against a Listing or User."
      consumes "application/json"
      produces "application/json"
      security [ { bearer: [] } ]

      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client,         in: :header, type: :string, required: true
      parameter name: :uid,            in: :header, type: :string, required: true
      parameter name: :report, in: :body, schema: {
        type: :object,
        properties: {
          report: {
            type: :object,
            properties: {
              reportable_type: { type: :string, enum: %w[Listing User] },
              reportable_id:   { type: :integer },
              reason:          { type: :string },
              description:     { type: :string }
            },
            required: %w[reportable_type reportable_id reason]
          }
        }
      }

      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }
      let(:report) do
        {
          report: {
            reportable_type: "Listing",
            reportable_id:   listing.id,
            reason:          "spam",
            description:     "Looks like a scam"
          }
        }
      end

      response "401", "requires authentication" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }

        run_test! do |response|
          expect(response).to have_http_status(:unauthorized)
        end
      end

      response "201", "creates a report" do
        run_test! do |response|
          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)["message"]).to eq("Report submitted")
        end

        after do |example|
          example.metadata[:response][:content] = {
            "application/json" => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
      end

      response "422", "rejects duplicate report for the same content" do
        before do
          create(:report, reporter: reporter, reportable: listing, reason: :spam)
        end

        run_test! do |response|
          expect(response).to have_http_status(:unprocessable_content)
          body = JSON.parse(response.body)
          expect(body["errors"]).to be_present
        end
      end

      response "422", "rejects reporting own listing" do
        let(:own_listing) { create(:listing, user: reporter) }
        let(:report) do
          {
            report: {
              reportable_type: "Listing",
              reportable_id:   own_listing.id,
              reason:          "spam"
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:unprocessable_content)
          expect(JSON.parse(response.body)["errors"]).to be_present
        end
      end
    end
  end

  # ── Isolation / non-RSwag tests ──────────────────────────────────────────────

  describe "GET /api/v1/reports — isolation" do
    it "does not return another user's reports" do
      other         = create(:user)
      other_listing = create(:listing)
      my_listing    = create(:listing)
      create(:report, reporter: other,    reportable: other_listing, reason: :spam)
      create(:report, reporter: reporter, reportable: my_listing,    reason: :fraud)

      get "/api/v1/reports", headers: headers, as: :json

      data = JSON.parse(response.body)
      expect(data["reports"].length).to eq(1)
      expect(data["reports"].first["reason"]).to eq("fraud")
    end

    it "assigns the current user as reporter on POST" do
      params = { report: { reportable_type: "Listing", reportable_id: listing.id, reason: "spam" } }
      post "/api/v1/reports", params: params, headers: headers, as: :json
      expect(Report.last.reporter).to eq(reporter)
    end

    it "controller source contains no bare render json: literal" do
      controller_source = File.read(
        Rails.root.join("app/controllers/api/v1/reports_controller.rb")
      )
      expect(controller_source).not_to include("render json:")
    end
  end
end
