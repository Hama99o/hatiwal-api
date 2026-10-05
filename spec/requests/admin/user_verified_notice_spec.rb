require "rails_helper"

# An admin switching the verified badge ON sends the "you are verified" Support
# message (SupportNoticeJob); other edits, and switching it off, send nothing.
RSpec.describe "Admin verifies a user", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, password: "changeme123!") }

  before { sign_in admin, scope: :admin_user }

  def update_user(user, attrs)
    patch admin_user_path(user), params: { user: attrs }
  end

  it "queues the verified notice when the badge goes from off to on" do
    user = create(:user, verified: false)

    expect { update_user(user, verified: "1") }
      .to have_enqueued_job(SupportNoticeJob).with(user.id, "user_verified")
    expect(user.reload).to be_verified
  end

  it "queues nothing when an already verified user is edited" do
    user = create(:user, verified: true)

    expect { update_user(user, verified: "1") }.not_to have_enqueued_job(SupportNoticeJob)
  end

  it "queues nothing when the badge is switched off" do
    user = create(:user, verified: true)

    expect { update_user(user, verified: "0") }.not_to have_enqueued_job(SupportNoticeJob)
    expect(user.reload).not_to be_verified
  end
end
