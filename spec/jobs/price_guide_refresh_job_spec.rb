require "rails_helper"

# IDEA-4: the nightly rebuild of every price-guide bucket.
RSpec.describe PriceGuideRefreshJob, type: :job do
  it "rebuilds the buckets" do
    expect(PriceGuides::Builder).to receive(:call)
    described_class.perform_now
  end

  it "is scheduled nightly in production" do
    expect(YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "price_guide_refresh", "class")).to eq("PriceGuideRefreshJob")
  end
end
