require "rails_helper"

# OFFLINE phase 2a (docs/OFFLINE_MODE.md §10.1).
RSpec.describe IdempotencyKey, type: :model do
  it "is unique per user and key (the index that makes concurrent retries safe)" do
    first = create(:idempotency_key)
    expect { create(:idempotency_key, user: first.user, key: first.key) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create(:idempotency_key, key: first.key)).to be_persisted # another user
  end

  it "accepts a UUID and rejects junk" do
    expect(described_class.valid_key?(SecureRandom.uuid)).to be(true)
    expect(described_class.valid_key?("short")).to be(false)
    expect(described_class.valid_key?("x y z with spaces")).to be(false)
    expect(described_class.valid_key?("a" * 65)).to be(false)
    expect(described_class.valid_key?(nil)).to be(false)
  end

  it "is gone with its user" do
    row = create(:idempotency_key)
    row.user.delete
    expect(described_class.exists?(row.id)).to be(false)
  end

  describe "#take_over_if_stale! (QA audit 2026-10-27 A3)" do
    it "takes over an in-progress row older than IN_PROGRESS_TTL for exactly one caller" do
      row = create(:idempotency_key, status: :in_progress, updated_at: (described_class::IN_PROGRESS_TTL + 1.minute).ago)
      other = described_class.find(row.id) # a second retry, arriving at the same moment
      expect(row.take_over_if_stale!).to be(true)
      expect(other.take_over_if_stale!).to be(false)
    end

    it "leaves a recent in-progress row and a completed row alone" do
      expect(create(:idempotency_key, status: :in_progress, updated_at: 1.minute.ago).take_over_if_stale!).to be(false)
      expect(create(:idempotency_key, status: :completed, updated_at: 1.hour.ago).take_over_if_stale!).to be(false)
    end
  end
end

RSpec.describe PurgeIdempotencyKeysJob, type: :job do
  it "forgets keys older than 30 days and keeps the rest" do
    old = create(:idempotency_key, created_at: (IdempotencyKey::KEPT_FOR + 1.day).ago)
    recent = create(:idempotency_key, created_at: 1.day.ago)
    described_class.perform_now
    expect(IdempotencyKey.exists?(old.id)).to be(false)
    expect(IdempotencyKey.exists?(recent.id)).to be(true)
  end
end
