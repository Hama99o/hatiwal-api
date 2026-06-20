require "rails_helper"

RSpec.describe Notifications::ExpoPushService do
  let(:token) { "ExponentPushToken[abc123]" }

  def stub_expo(body_hash)
    response = instance_double(Net::HTTPResponse, body: body_hash.to_json)
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
  end

  it "returns missing_token when token is blank" do
    result = described_class.deliver(token: "", title: "t", body: "b")
    expect(result.ok).to be false
    expect(result.error).to eq(:missing_token)
  end

  it "returns invalid_token for a non-Expo token (never calls the network)" do
    expect_any_instance_of(Net::HTTP).not_to receive(:request)
    result = described_class.deliver(token: "not-a-real-token", title: "t", body: "b")
    expect(result.ok).to be false
    expect(result.error).to eq(:invalid_token)
  end

  it "returns ok for a successful Expo response" do
    stub_expo("data" => { "status" => "ok", "id" => "receipt-1" })
    result = described_class.deliver(token: token, title: "Ahmad", body: "Salaam", data: { conversationId: 3 })
    expect(result.ok).to be true
    expect(result.error).to be_nil
  end

  it "surfaces the Expo error type (DeviceNotRegistered) so the caller can drop the token" do
    stub_expo("data" => { "status" => "error", "details" => { "error" => "DeviceNotRegistered" } })
    result = described_class.deliver(token: token, title: "t", body: "b")
    expect(result.ok).to be false
    expect(result.error).to eq("DeviceNotRegistered")
  end

  it "never raises on a network failure — returns ok:false with :exception" do
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Errno::ECONNREFUSED)
    result = described_class.deliver(token: token, title: "t", body: "b")
    expect(result.ok).to be false
    expect(result.error).to eq(:exception)
  end

  it "sends the expected payload to the Expo endpoint" do
    captured = nil
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, req|
      captured = JSON.parse(req.body)
      instance_double(Net::HTTPResponse, body: { "data" => { "status" => "ok" } }.to_json)
    end

    described_class.deliver(token: token, title: "Ahmad", body: "Salaam", data: { conversationId: 7 })

    expect(captured["to"]).to eq(token)
    expect(captured["title"]).to eq("Ahmad")
    expect(captured["body"]).to eq("Salaam")
    expect(captured["data"]).to eq("conversationId" => 7)
    expect(captured["priority"]).to eq("high")
  end
end
