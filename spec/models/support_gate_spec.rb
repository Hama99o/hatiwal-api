require "rails_helper"

# The admin-side gate for in-app messages (docs/SUPPORT_MESSAGING.md).
RSpec.describe "Support gate (admin side)" do
  let(:user) { create(:user) }

  def flag(on)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SUPPORT_ADMIN_INITIATE", "false").and_return(on ? "true" : "false")
  end

  it "refuses a user with no support thread while the flag is off, and creates nothing" do
    flag(false)

    expect(Conversation.admin_can_message?(user)).to be(false)
    expect(Conversation.admin_message_refusal(user)).to include("SUPPORT_ADMIN_INITIATE")
    expect(Conversation.admin_support_thread_for(user)).to be_nil
    expect(Conversation.kind_support.count).to eq(0)
  end

  it "allows a user who opened a thread themselves (they are on the new app), flag off" do
    flag(false)
    thread = Conversation.support_thread_for!(user) # the user-initiated API path

    expect(Conversation.admin_support_thread_for(user)).to eq(thread)
  end

  it "creates the thread once the flag is on" do
    flag(true)

    expect(Conversation.admin_support_thread_for(user)).to be_kind_support
  end

  it "never allows the Support account or a deleted user" do
    flag(true)

    expect(Conversation.admin_can_message?(User.support_account!)).to be(false)
    expect(Conversation.admin_can_message?(create(:user, deleted_at: 1.day.ago))).to be(false)
  end

  # STRUCTURAL GUARD, not a redundant test. Every other check here guards code
  # that exists today; this one guards admin code nobody has written yet.
  # Conversation.support_thread_for! creates a thread with NO gate — correct for
  # the user's own "Contact support" (only the new app has it), wrong for any
  # admin feature, which would put a "removed listing" chat in front of v1.0.4
  # users. Admin code must go through Conversation.admin_support_thread_for.
  # Do not delete this because it "only greps": that is the point.
  it "no admin controller, job, mailer, service or model calls the ungated support_thread_for!" do
    # Models too: bulk in-app delivery lives in one (AdminBulkInAppDelivery).
    # conversation.rb is where it is DEFINED; that is the only exemption.
    files = Dir[Rails.root.join("app/{controllers/admin,jobs,mailers,services,models}/**/*.rb")]
    offenders = (files - [ Rails.root.join("app/models/conversation.rb").to_s ]).select do |file|
      File.read(file).include?("support_thread_for!")
    end

    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to eq([])
  end
end
