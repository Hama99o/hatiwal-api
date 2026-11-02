require "rails_helper"

# privacy-b: the viewer's shops must never outlive the request they were read in.
RSpec.describe Current do
  it "forgets the viewer's shops on reset (the next request on this thread starts empty)" do
    member = create(:user)
    shop = create(:shop)
    shop.shop_members.create!(user: member, role: :staff)

    Current.viewer_resolver = -> { member }
    expect(Current.viewer_shop_ids).to include(shop.id)

    Current.reset
    expect(Current.viewer_shop_ids).to be_empty
    Current.viewer_resolver = -> { nil }
    expect(Current.viewer_shop_ids).to be_empty
  end
end
