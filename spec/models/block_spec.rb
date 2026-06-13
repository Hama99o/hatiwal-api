require "rails_helper"

RSpec.describe Block, type: :model do
  describe "associations" do
    it { should belong_to(:blocker).class_name("User") }
    it { should belong_to(:blocked).class_name("User") }
  end

  describe "validations" do
    subject { build(:block) }

    it { should validate_uniqueness_of(:blocker_id).scoped_to(:blocked_id) }

    it "is invalid when blocker and blocked are the same user" do
      user = create(:user)
      block = build(:block, blocker: user, blocked: user)
      expect(block).not_to be_valid
      expect(block.errors[:blocked_id]).to include("cannot block yourself")
    end
  end
end
