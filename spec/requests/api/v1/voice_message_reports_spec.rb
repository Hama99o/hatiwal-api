require "rails_helper"

# A voice message can be reported on its own (1.2.1, docs/VOICE_MESSAGES.md §8.2):
# abuse can come by voice, and a report on the person alone never let a
# moderator hear it. Only the OTHER side of the chat may report one.
RSpec.describe "Reporting a voice message", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:buyer)        { create(:user) }
  let(:seller)       { create(:user) }
  let(:listing)      { create(:listing, :active, user: seller) }
  let(:conversation) { create(:conversation, buyer: buyer, listing: listing) }
  let(:voice)        { create(:message, :voice, conversation: conversation, user: seller) }

  def report(message, as:, reason: "inappropriate")
    post "/api/v1/reports",
         params: { report: { reportable_type: "Message", reportable_id: message.id, reason: reason } },
         headers: auth_headers_for(as), as: :json
  end

  it "the other side reports it" do
    report(voice, as: buyer)

    expect(response).to have_http_status(:created)
    expect(Report.last).to have_attributes(reportable: voice, reporter: buyer)
  end

  it "shows in the reporter's list as a voice message" do
    report(voice, as: buyer)
    get "/api/v1/reports", headers: auth_headers_for(buyer), as: :json

    row = response.parsed_body["reports"].first
    expect(row).to include("reportable_type" => "Message", "reportable_label" => "🎤 0:12")
  end

  it "not its sender" do
    report(voice, as: seller)

    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:forbidden)
    expect(Report.count).to eq(0)
  end

  it "not someone outside the chat" do
    report(voice, as: create(:user))

    expect(response).to have_http_status(:forbidden)
    expect(Report.count).to eq(0)
  end

  it "only voice messages (a text is reported through its sender, as before)" do
    text = create(:message, conversation: conversation, user: seller)
    report(text, as: buyer)

    expect(response).not_to have_http_status(:created)
    expect(Report.count).to eq(0)
  end

  it "not a deleted one (nothing left to hear)" do
    voice.soft_delete!
    report(voice, as: buyer)

    expect(response).not_to have_http_status(:created)
  end

  it "once per reporter" do
    report(voice, as: buyer)
    report(voice, as: buyer)

    expect(response).to have_http_status(:unprocessable_content)
    expect(Report.count).to eq(1)
  end

  describe "the admin report page" do
    let(:admin) { create(:admin_user) }

    it "plays the clip, names its sender and can warn them" do
      report(voice, as: buyer)
      sign_in admin, scope: :admin_user
      get "/admin/reports/#{Report.last.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<audio")
      expect(response.body).to include(seller.full_name)
      expect(response.body).to include("Warn sender &amp; resolve")
    end
  end
end
