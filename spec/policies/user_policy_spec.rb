require "rails_helper"

RSpec.describe UserPolicy do
  let(:user) { build_stubbed(:user) }

  it "lets a user update their own location guess" do
    expect(described_class.new(user, user).update_location_guess?).to be(true)
  end

  it "forbids updating someone else's" do
    expect(described_class.new(user, build_stubbed(:user)).update_location_guess?).to be(false)
  end
end
