require "rails_helper"

RSpec.describe Admin::FlagPolicy do
  let(:admin) { build(:admin_user) }
  let(:user) { build(:user) }
  let(:open_flag) { build(:flag, status: :open) }
  let(:closed_flag) { build(:flag, status: :dismissed) }

  def policy(who, flag) = described_class.new(who, flag)

  %i[index? show?].each do |action|
    describe "##{action}" do
      it("allows an admin") { expect(policy(admin, open_flag).public_send(action)).to be(true) }
      it("denies a marketplace user") { expect(policy(user, open_flag).public_send(action)).to be(false) }
      it("denies nobody signed in") { expect(policy(nil, open_flag).public_send(action)).to be(false) }
    end
  end

  %i[dismiss? take_down? take_down_warn?].each do |action|
    describe "##{action}" do
      it("allows an admin on an open flag") { expect(policy(admin, open_flag).public_send(action)).to be(true) }
      it("denies an admin on a decided flag") { expect(policy(admin, closed_flag).public_send(action)).to be(false) }
      it("denies a marketplace user") { expect(policy(user, open_flag).public_send(action)).to be(false) }
    end
  end

  describe "Scope" do
    it "is every flag for an admin and none for anyone else" do
      flag = create(:flag)
      expect(described_class::Scope.new(admin, Flag).resolve).to contain_exactly(flag)
      expect(described_class::Scope.new(user, Flag).resolve).to be_empty
    end
  end
end
