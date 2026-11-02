require "swagger_helper"

# POST /api/v1/cable_ticket — a single-use pass for the chat's live connection,
# for clients that cannot set WebSocket headers (hatiwal-web): the URL carries
# `?ticket=…` (one connect, TTL 60 s) instead of the session itself.
RSpec.describe "Api::V1::CableTickets", type: :request do
  let(:user) { create(:user) }

  path "/api/v1/cable_ticket" do
    post "a single-use ticket for the cable's connect URL" do
      tags "Chat"
      description "Signed in. Returns a random ticket worth ONE cable connect (`wss://…/hatiwal-cable?ticket=…`) " \
                  "within `expires_in` seconds; only its digest is stored. Cache-Control: no-store."
      produces "application/json"
      security [ { bearer: [] } ]
      parameter name: :"access-token", in: :header, type: :string, required: true
      parameter name: :client, in: :header, type: :string, required: true
      parameter name: :uid, in: :header, type: :string, required: true

      let(:headers) { auth_headers_for(user) }
      let(:"access-token") { headers["access-token"] }
      let(:client)         { headers["client"] }
      let(:uid)            { headers["uid"] }

      response "201", "issued" do
        schema type: :object,
               properties: { ticket: { type: :string }, expires_in: { type: :integer } },
               required: %w[ticket expires_in]

        run_test! do
          body = JSON.parse(response.body)
          expect(body["expires_in"]).to eq(CableTicket::TTL.to_i)
          expect(CableTicket.consume(body["ticket"])).to eq(user)
          expect(response.headers["Cache-Control"]).to include("no-store")
        end
      end

      response "401", "not signed in" do
        let(:"access-token") { nil }
        let(:client)         { nil }
        let(:uid)            { nil }

        run_test! { expect(CableTicket.count).to eq(0) }
      end
    end
  end

  describe "who may have one" do
    it "nobody signed in: 401, nothing issued" do
      post "/api/v1/cable_ticket"
      expect(response).to have_http_status(:unauthorized)
      expect(CableTicket.count).to eq(0)
    end

    it "a banned user: refused, nothing issued" do
      headers = auth_headers_for(user)
      user.update!(status: :banned)
      post "/api/v1/cable_ticket", headers: headers
      expect(response.status).to be_in([ 401, 403 ])
      expect(CableTicket.count).to eq(0)
    end

    it "the ticket is the caller's: it connects as them, never as anyone else" do
      other = create(:user)
      post "/api/v1/cable_ticket", headers: auth_headers_for(other)
      expect(CableTicket.consume(JSON.parse(response.body)["ticket"])).to eq(other)
    end
  end
end
