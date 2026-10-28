require "rails_helper"

# A single-use, short-lived pass for the chat's live connection (the cable).
# A browser cannot set WebSocket headers, so hatiwal-web had to put the whole
# session in the URL; now it puts a ticket there instead, worth one connect
# within TTL (privacy review 2026-10-28).
RSpec.describe CableTicket, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it "issues a random ticket and stores only its digest, never the ticket itself" do
    ticket = described_class.issue!(user)

    expect(ticket).to match(/\A[A-Za-z0-9_-]{40,}\z/)
    row = described_class.sole
    expect(row.user).to eq(user)
    expect(row.digest).to eq(Digest::SHA256.hexdigest(ticket))
    expect(row.attributes.values.map(&:to_s)).not_to include(ticket)
    expect(row.expires_at).to be_within(2.seconds).of(described_class::TTL.from_now)
  end

  it "two tickets are never the same" do
    expect(described_class.issue!(user)).not_to eq(described_class.issue!(user))
  end

  it "is worth ONE connect: the first consume gives its user, a replay nothing" do
    ticket = described_class.issue!(user)

    expect(described_class.consume(ticket)).to eq(user)
    expect(described_class.consume(ticket)).to be_nil
    expect(described_class.count).to eq(0)
  end

  it "is refused once expired (and the row goes)" do
    ticket = described_class.issue!(user)
    travel(described_class::TTL + 1.second) do
      expect(described_class.consume(ticket)).to be_nil
    end
    expect(described_class.count).to eq(0)
  end

  it "an unknown, empty, non-string or oversized ticket gives nothing" do
    described_class.issue!(user)
    [ "nope", "", nil, 42, "x" * 5_000 ].each { |bad| expect(described_class.consume(bad)).to be_nil }
    expect(described_class.count).to eq(1) # someone else's real ticket is untouched
  end

  it "expired scope: only the ones past their TTL" do
    old = described_class.issue!(user)
    travel(described_class::TTL + 1.second) do
      fresh = described_class.issue!(user)
      expect(described_class.expired.count).to eq(1)
      expect(described_class.consume(fresh)).to eq(user)
      expect(described_class.consume(old)).to be_nil
    end
  end

  context "two connects with one ticket at the same time", db_truncation: true do
    it "exactly one of them gets the user" do
      ticket = described_class.issue!(user)
      results = Array.new(4) { Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.consume(ticket) } } }.map(&:value)

      expect(results.compact).to eq([ user ])
    end
  end
end
