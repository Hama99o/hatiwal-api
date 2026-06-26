require "rails_helper"

RSpec.describe UserSerializer, type: :serializer do
  describe ":public view — last_active_label" do
    subject(:label) do
      result = described_class.render_as_hash(user, view: :public, current_user: viewer)
      result[:last_active_label]
    end

    let(:viewer) { create(:user) }

    context "when last_sign_in_at is nil" do
      let(:user) { create(:user, last_sign_in_at: nil) }

      it "returns nil" do
        expect(label).to be_nil
      end
    end

    context "when last_sign_in_at was 1 hour ago (< 24h)" do
      let(:user) { create(:user, last_sign_in_at: 1.hour.ago) }

      it 'returns "today"' do
        expect(label).to eq("today")
      end
    end

    context "when last_sign_in_at was 23 hours ago (boundary — still today)" do
      let(:user) { create(:user, last_sign_in_at: 23.hours.ago) }

      it 'returns "today"' do
        expect(label).to eq("today")
      end
    end

    context "when last_sign_in_at was 3 days ago (< 7d)" do
      let(:user) { create(:user, last_sign_in_at: 3.days.ago) }

      it 'returns "this_week"' do
        expect(label).to eq("this_week")
      end
    end

    context "when last_sign_in_at was 6 days ago (boundary — still this_week)" do
      let(:user) { create(:user, last_sign_in_at: 6.days.ago) }

      it 'returns "this_week"' do
        expect(label).to eq("this_week")
      end
    end

    context "when last_sign_in_at was 20 days ago (< 30d)" do
      let(:user) { create(:user, last_sign_in_at: 20.days.ago) }

      it 'returns "this_month"' do
        expect(label).to eq("this_month")
      end
    end

    context "when last_sign_in_at was 29 days ago (boundary — still this_month)" do
      let(:user) { create(:user, last_sign_in_at: 29.days.ago) }

      it 'returns "this_month"' do
        expect(label).to eq("this_month")
      end
    end

    context "when last_sign_in_at was 60 days ago (> 30d)" do
      let(:user) { create(:user, last_sign_in_at: 60.days.ago) }

      it "returns nil" do
        expect(label).to be_nil
      end
    end

    context "when last_sign_in_at was exactly 30 days ago (boundary — not this_month)" do
      let(:user) { create(:user, last_sign_in_at: 30.days.ago) }

      it "returns nil" do
        expect(label).to be_nil
      end
    end
  end

  describe ":public view — raw timestamp not exposed" do
    let(:viewer) { create(:user) }
    let(:user)   { create(:user, last_sign_in_at: 1.hour.ago) }

    subject(:result) do
      described_class.render_as_hash(user, view: :public, current_user: viewer)
    end

    it "does not include last_sign_in_at in the public view" do
      expect(result).not_to have_key(:last_sign_in_at)
    end

    it "includes last_active_label as a string" do
      expect(result[:last_active_label]).to eq("today")
    end
  end

  describe ":me view — last_active_label not present" do
    let(:user) { create(:user, last_sign_in_at: 1.hour.ago) }

    subject(:result) do
      described_class.render_as_hash(user, view: :me)
    end

    it "does not include last_active_label in the :me view" do
      expect(result).not_to have_key(:last_active_label)
    end
  end

  describe ":public view — share_url field" do
    let(:viewer) { create(:user) }
    let(:user)   { create(:user) }

    context "when PUBLIC_SHARE_BASE_URL is set" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.example.com")
      end

      it "returns a full https URL with /u/<id> path" do
        result = described_class.render_as_hash(user, view: :public, current_user: viewer)
        expect(result[:share_url]).to eq("https://hatiwal.example.com/u/#{user.id}")
      end

      it "returns a String" do
        result = described_class.render_as_hash(user, view: :public, current_user: viewer)
        expect(result[:share_url]).to be_a(String)
      end

      it "handles a trailing slash in the base URL gracefully" do
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("https://hatiwal.example.com/")
        result = described_class.render_as_hash(user, view: :public, current_user: viewer)
        expect(result[:share_url]).to eq("https://hatiwal.example.com/u/#{user.id}")
      end
    end

    context "when PUBLIC_SHARE_BASE_URL is not set (nil)" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return(nil)
      end

      it "returns nil" do
        result = described_class.render_as_hash(user, view: :public, current_user: viewer)
        expect(result[:share_url]).to be_nil
      end
    end

    context "when PUBLIC_SHARE_BASE_URL is an empty string" do
      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PUBLIC_SHARE_BASE_URL", nil).and_return("")
      end

      it "returns nil" do
        result = described_class.render_as_hash(user, view: :public, current_user: viewer)
        expect(result[:share_url]).to be_nil
      end
    end
  end

  describe ":public view — share_url not present in :me view" do
    let(:user) { create(:user) }

    it "does not include share_url in the :me view" do
      result = described_class.render_as_hash(user, view: :me)
      expect(result).not_to have_key(:share_url)
    end
  end

  describe ":public view — share_url not present in :minimal view" do
    let(:user) { create(:user) }

    it "does not include share_url in the :minimal view" do
      result = described_class.render_as_hash(user, view: :minimal)
      expect(result).not_to have_key(:share_url)
    end
  end

  describe ":public view — away mode (is_away + away_until)" do
    let(:viewer) { create(:user) }

    subject(:result) do
      described_class.render_as_hash(user, view: :public, current_user: viewer)
    end

    context "when away_until is nil (not away)" do
      let(:user) { create(:user, away_until: nil) }

      it "returns is_away as false" do
        expect(result[:is_away]).to be(false)
      end

      it "returns away_until as nil" do
        expect(result[:away_until]).to be_nil
      end
    end

    context "when away_until is in the past (auto-expired, no longer away)" do
      let(:user) do
        u = create(:user)
        u.update_column(:away_until, 2.days.ago)
        u
      end

      it "returns is_away as false" do
        expect(result[:is_away]).to be(false)
      end

      it "returns away_until as nil (stale past date never surfaces to public)" do
        expect(result[:away_until]).to be_nil
      end
    end

    context "when away_until is in the future (currently away)" do
      let(:future_date) { 5.days.from_now }
      let(:user) { create(:user, away_until: future_date) }

      it "returns is_away as true" do
        expect(result[:is_away]).to be(true)
      end

      it "returns away_until as an ISO-8601 string" do
        expect(result[:away_until]).to be_a(String)
        expect { Time.parse(result[:away_until]) }.not_to raise_error
      end
    end
  end

  describe ":me view — away mode (is_away + away_until)" do
    subject(:result) do
      described_class.render_as_hash(user, view: :me)
    end

    context "when away_until is nil" do
      let(:user) { create(:user, away_until: nil) }

      it "includes is_away as false" do
        expect(result[:is_away]).to be(false)
      end

      it "includes away_until as nil" do
        expect(result).to have_key(:away_until)
        expect(result[:away_until]).to be_nil
      end
    end

    context "when away_until is a past date (auto-expired)" do
      let(:user) do
        u = create(:user)
        u.update_column(:away_until, 1.day.ago)
        u
      end

      it "includes is_away as false (auto-expired)" do
        expect(result[:is_away]).to be(false)
      end

      it "includes away_until as nil (not away, so nil returned)" do
        # :me view returns away_until only when user is currently away
        expect(result[:away_until]).to be_nil
      end
    end

    context "when away_until is a future date (currently away)" do
      let(:user) { create(:user, away_until: 3.days.from_now) }

      it "includes is_away as true" do
        expect(result[:is_away]).to be(true)
      end

      it "includes away_until as an ISO-8601 string" do
        expect(result[:away_until]).to be_a(String)
        expect { Time.parse(result[:away_until]) }.not_to raise_error
      end
    end
  end

  describe ":minimal view — away fields not exposed" do
    let(:user) { create(:user, away_until: 3.days.from_now) }

    it "does not include away_until in the :minimal view" do
      result = described_class.render_as_hash(user, view: :minimal)
      expect(result).not_to have_key(:away_until)
    end

    it "does not include is_away in the :minimal view" do
      result = described_class.render_as_hash(user, view: :minimal)
      expect(result).not_to have_key(:is_away)
    end
  end
end
