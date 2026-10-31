require "swagger_helper"

# IDEA-4: the price range for a subcategory + currency. Public; only aggregates.
# A buyer-facing ask (`audience=buyer`) is answered only when the server flag
# PRICE_GUIDE_BUYERS is on (owner's decision, default off).
RSpec.describe "Api::V1::PriceGuide", type: :request do
  let(:phones) { create(:category, :with_parent) }

  path "/api/v1/price_guide" do
    get "price range of similar sold items" do
      tags "Price guide"
      description "IDEA-4: P25–P75 of sold prices (last 90 days) for a subcategory + currency, published only with ≥ 5 " \
                  "sales from ≥ 3 sellers. Otherwise `{ available: false }` and nothing else. `audience=buyer` is " \
                  "answered only when the server enables it for buyers."
      produces "application/json"
      parameter name: :category_id, in: :query, type: :integer
      parameter name: :currency, in: :query, type: :string
      parameter name: :audience, in: :query, type: :string, required: false, enum: %w[seller buyer]

      let(:category_id) { phones.id }
      let(:currency) { "AFN" }

      response "200", "a published range" do
        before { PriceGuide.create!(category: phones, currency: "AFN", sales_count: 7, sellers_count: 4, low: 8_000, high: 11_000, available: true, refreshed_at: Time.current) }

        schema type: :object, properties: {
          price_guide: { type: :object, properties: {
            available: { type: :boolean }, low: { type: :number }, high: { type: :number },
            count: { type: :integer }, currency: { type: :string }, window_days: { type: :integer }
          }, required: %w[available] }
        }

        run_test! do
          expect(response.parsed_body["price_guide"]).to eq(
            "available" => true, "low" => 8000.0, "high" => 11_000.0, "count" => 7, "currency" => "AFN", "window_days" => 90
          )
        end
      end

      response "200", "not enough sales: available false, and nothing else" do
        before { PriceGuide.create!(category: phones, currency: "AFN", sales_count: 4, sellers_count: 2, available: false, refreshed_at: Time.current) }

        run_test! do
          expect(response.parsed_body["price_guide"]).to eq("available" => false)
        end
      end

      response "200", "a buyer asks while the buyer flag is off: hidden" do
        let(:audience) { "buyer" }
        before { PriceGuide.create!(category: phones, currency: "AFN", sales_count: 7, sellers_count: 4, low: 8_000, high: 11_000, available: true, refreshed_at: Time.current) }

        run_test! do
          expect(response.parsed_body["price_guide"]).to eq("available" => false)
        end
      end
    end
  end

  it "a buyer sees it once the server enables it" do
    PriceGuide.create!(category: phones, currency: "AFN", sales_count: 7, sellers_count: 4, low: 8_000, high: 11_000, available: true, refreshed_at: Time.current)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("PRICE_GUIDE_BUYERS", "0").and_return("1")
    get "/api/v1/price_guide", params: { category_id: phones.id, currency: "AFN", audience: "buyer" }
    expect(response.parsed_body.dig("price_guide", "available")).to be true
  end

  it "no bucket at all: available false" do
    get "/api/v1/price_guide", params: { category_id: phones.id, currency: "AFN" }
    expect(response.parsed_body["price_guide"]).to eq("available" => false)
  end
end
