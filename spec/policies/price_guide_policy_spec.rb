require "rails_helper"

RSpec.describe PriceGuidePolicy do
  it "anyone can read the guide (aggregates only)" do
    expect(described_class.new(nil, PriceGuide).show?).to be true
  end

  it "admin policy: an AdminUser reads the buckets; nobody edits them" do
    admin = Admin::PriceGuidePolicy.new(create(:admin_user), PriceGuide)
    expect(admin.index?).to be true
    expect(%i[create? update? destroy?].map { |a| admin.public_send(a) }).to all(be false)
    expect(Admin::PriceGuidePolicy.new(create(:user), PriceGuide).index?).to be false
  end
end
