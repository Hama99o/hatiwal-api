require "rails_helper"

RSpec.describe Admin::ProhibitedTermPolicy do
  let(:admin) { build(:admin_user) }
  let(:user) { build(:user) }
  let(:term) { build(:prohibited_term) }

  %i[index? show? new? create? edit? update? destroy?].each do |action|
    describe "##{action}" do
      it("allows an admin") { expect(described_class.new(admin, term).public_send(action)).to be(true) }
      it("denies a marketplace user") { expect(described_class.new(user, term).public_send(action)).to be(false) }
      it("denies nobody signed in") { expect(described_class.new(nil, term).public_send(action)).to be(false) }
    end
  end

  describe "Scope" do
    it "is every term for an admin and none for anyone else" do
      term = create(:prohibited_term)
      expect(described_class::Scope.new(admin, ProhibitedTerm).resolve).to contain_exactly(term)
      expect(described_class::Scope.new(user, ProhibitedTerm).resolve).to be_empty
    end
  end
end
