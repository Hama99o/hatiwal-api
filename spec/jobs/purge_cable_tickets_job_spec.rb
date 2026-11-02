require "rails_helper"

RSpec.describe PurgeCableTicketsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  it "forgets the tickets past their TTL, keeps the live ones" do
    user = create(:user)
    old = CableTicket.issue!(user)
    travel(CableTicket::TTL + 1.second) do
      live = CableTicket.issue!(user)
      described_class.perform_now
      expect(CableTicket.count).to eq(1)
      expect(CableTicket.consume(live)).to eq(user)
      expect(CableTicket.consume(old)).to be_nil
    end
  end
end
