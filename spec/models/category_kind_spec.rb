require "rails_helper"

RSpec.describe Category, "kind" do
  it "defaults to item" do
    expect(create(:category).kind).to eq(Category::KIND_ITEM)
  end

  it "refuses an unknown kind" do
    expect(build(:category, kind: "car")).not_to be_valid
  end

  it "makes a subcategory carry its parent's kind" do
    root = create(:category, kind: Category::KIND_STAY)
    child = create(:category, parent: root, kind: Category::KIND_ITEM)
    expect(child.reload.kind).to eq(Category::KIND_STAY)
    expect(child).to be_stay
  end

  it "passes a root's new kind down to its subcategories" do
    root = create(:category)
    child = create(:category, parent: root)
    root.update!(kind: Category::KIND_STAY)
    expect(child.reload.kind).to eq(Category::KIND_STAY)
  end
end
