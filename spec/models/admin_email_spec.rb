require "rails_helper"

RSpec.describe AdminEmail do
  it "is valid with a subject, body and an emailable user" do
    expect(build(:admin_email)).to be_valid
  end

  it "requires a subject and body" do
    expect(build(:admin_email, subject: "")).not_to be_valid
    expect(build(:admin_email, body: "")).not_to be_valid
  end

  it "refuses the Support account, deleted users and placeholder addresses" do
    deleted = create(:user, deleted_at: 1.day.ago)
    placeholder = create(:user)
    placeholder.update_column(:email, "deleted-9@deleted.invalid")

    [ User.support_account!, deleted, placeholder ].each do |user|
      email = build(:admin_email, user: user)
      expect(email).not_to be_valid
      expect(email.errors[:user].join).to include("can't be emailed")
    end
  end
end
