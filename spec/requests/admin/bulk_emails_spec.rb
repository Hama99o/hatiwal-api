require "rails_helper"

RSpec.describe "Admin bulk email", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }
  let!(:kabul_ps) { create(:user, city: "Kabul", confirmed_at: Time.current, preferred_language: "ps") }
  let!(:kabul_en) { create(:user, city: "Kabul", confirmed_at: Time.current, preferred_language: "en") }
  let!(:herat)    { create(:user, city: "Herat", confirmed_at: Time.current, preferred_language: "fa") }
  let(:content) do
    { "en" => { "subject" => "Hello Kabul", "body" => "News" }, "ps" => { "subject" => "سلام کابل", "body" => "خبرونه" } }
  end
  let(:draft) { { city: "Kabul", fallback_locale: "en", content: content } }

  before do
    sign_in admin, scope: :admin_user
    ActionMailer::Base.deliveries.clear
  end

  it "uses the users-index filters: the segment shown is the segment that receives" do
    get new_admin_bulk_email_path(city: "Kabul")

    expect(response.body).to include('id="admin-filter-bar"')
    expect(response.body[%r{<strong id="recipient-count".*?</strong>}m]).to include("2 will receive")
  end

  it "shows all four language boxes at once, each with its recipient count" do
    get new_admin_bulk_email_path(city: "Kabul")

    %w[en ps fa ur].each { |loc| expect(response.body).to include(%(data-locale="#{loc}")) }
    expect(response.body).to match(/data-locale="ps" data-count="1"/)
  end

  it "the users index links to bulk email with the same filters" do
    get admin_users_path(city: "Kabul")
    expect(response.body).to include('id="email-these-users"').and include("/admin/bulk_emails/new?city=Kabul")
  end

  it "previews every written language and names who gets the fallback" do
    post preview_admin_bulk_emails_path, params: draft.merge(city: nil)

    expect(response.body.scan('class="bulk-preview"').size).to eq(2)
    expect(response.body[%r{<p id="fallback-summary".*?</p>}m]).to include("1 Dari").and include("English")
  end

  it "won't send unless the typed number matches a FRESH recipient count" do
    post admin_bulk_emails_path, params: draft.merge(confirm_count: 3)
    expect(AdminBulkEmail.count).to eq(0)
    expect(response.body).to include("Type the number of people (2)")
  end

  it "refuses up front when the send would exceed the daily limit" do
    allow(Admin::MailQuota).to receive(:remaining).and_return(1)

    post admin_bulk_emails_path, params: draft.merge(confirm_count: 2)

    expect(AdminBulkEmail.count).to eq(0)
    expect(response.body).to include("Over the daily limit")
  end

  it "snapshots one row per recipient in their language, sends, and shows it in Messages" do
    perform_enqueued_jobs do
      post admin_bulk_emails_path, params: draft.merge(confirm_count: 2)
    end

    bulk = AdminBulkEmail.last
    expect(response).to redirect_to(admin_bulk_email_path(bulk))
    expect(bulk.admin_emails.pluck(:user_id, :locale)).to contain_exactly([ kabul_ps.id, "ps" ], [ kabul_en.id, "en" ])
    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly("Hello Kabul", "سلام کابل")
    expect(bulk.reload).to be_finished

    get admin_messages_path
    row = response.body[%r{<tr class="bulk-row".*?</tr>}m]
    expect(row).to include("2 people").and include("City: Kabul")
    # Regression: grouped counts are keyed by status NAME; this once read "0 sent".
    expect(row).to include("2 sent")
  end

  it "names the segment by the filters' own labels" do
    get new_admin_bulk_email_path(created_from: "2026-09-01", created_to: "2026-09-30")
    expect(response.body).to include("Joined from 2026-09-01 to 2026-09-30")
  end

  it "the campaign page shows every language version in full, with how many got it" do
    perform_enqueued_jobs { post admin_bulk_emails_path, params: draft.merge(confirm_count: 2) }

    get admin_bulk_email_path(AdminBulkEmail.last)

    sent = response.body[%r{<section id="bulk-sent".*?</section>}m]
    ps = sent[%r{<div class="hw-lang bulk-sent-version" data-locale="ps">.*?</div>\s*</div>}m]
    en = sent[%r{<div class="hw-lang bulk-sent-version" data-locale="en">.*?</div>\s*</div>}m]
    expect(ps).to include("Pashto").and include("1 by email").and include("سلام کابل").and include("خبرونه")
    expect(en).to include("(fallback)").and include("1 by email").and include("Hello Kabul").and include("News")
  end

  it "excludes unsubscribed users automatically" do
    kabul_en.update!(email_opt_out_at: 1.day.ago)

    get new_admin_bulk_email_path(city: "Kabul")

    expect(response.body).to include("1 unsubscribed")
    expect(response.body[%r{<strong id="recipient-count".*?</strong>}m]).to include("1 will receive")
  end

  it "Stop cancels everyone not yet sent" do
    post admin_bulk_emails_path, params: draft.merge(confirm_count: 2) # job enqueued, not run
    bulk = AdminBulkEmail.last

    patch stop_admin_bulk_email_path(bulk)

    expect(bulk.reload).to be_stopped
    expect(bulk.admin_emails.cancelled.count).to eq(2)
    perform_enqueued_jobs
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "in development, refuses (loudly) a segment containing anyone but the mail account" do
    allow(Rails.env).to receive(:development?).and_return(true)

    post admin_bulk_emails_path, params: draft.merge(confirm_count: 2)

    expect(AdminBulkEmail.count).to eq(0)
    expect(response.body).to include("Refused, nothing sent").and include("dev SMTP sends real mail")
  end

  it "test copies go only to the admin and carry a dead unsubscribe link" do
    post test_admin_bulk_emails_path, params: draft

    expect(ActionMailer::Base.deliveries.map(&:to).uniq).to eq([ [ admin.email ] ])
    expect(ActionMailer::Base.deliveries.size).to eq(2) # one per written language
    expect(ActionMailer::Base.deliveries.first.html_part.body.decoded).to include("/unsubscribe/test-copy")
  end
end
