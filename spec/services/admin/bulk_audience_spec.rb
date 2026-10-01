require "rails_helper"

RSpec.describe Admin::BulkAudience do
  it "counts every exclusion and who will receive, per language" do
    create(:user, confirmed_at: Time.current, preferred_language: "ps")
    create(:user, confirmed_at: Time.current, preferred_language: "fa")
    create(:user, confirmed_at: nil)                                               # unconfirmed
    create(:user, confirmed_at: Time.current, email_opt_out_at: 1.day.ago)         # opted out
    create(:user, confirmed_at: Time.current, deleted_at: 1.day.ago)               # deleted
    User.support_account!                                                          # never counted

    a = described_class.new(User.all)

    expect([ a.matched_count, a.unconfirmed_count, a.opted_out_count, a.unreachable_count, a.recipients_count ])
      .to eq([ 5, 1, 1, 1, 2 ])
    expect(a.by_language).to include("ps" => 1, "fa" => 1, "en" => 0, "ur" => 0)
  end
end
