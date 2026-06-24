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
end
