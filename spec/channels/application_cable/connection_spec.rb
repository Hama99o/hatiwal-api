require "rails_helper"

# Privacy review 2026-10-28: the cable session used to ride in the URL's query
# string (?access_token=…&client=…&uid=<email>), and every proxy in front of the
# API may log request URLs. 1.2.0 apps send the devise_token_auth HEADERS
# instead; 1.1.x apps still send the query and keep working.
RSpec.describe ApplicationCable::Connection, type: :channel do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { user.create_new_auth_token } # { "access-token", "client", "uid", … }

  it "connects with the session in the headers, and needs no query string at all" do
    connect "/hatiwal-cable", headers: { "access-token" => auth["access-token"], "client" => auth["client"], "uid" => auth["uid"] }

    expect(connection.current_user).to eq(user)
    expect(connection.request.params.slice("access_token", "client", "uid")).to be_empty
  end

  it "still connects a 1.1.x app that puts the session in the query string" do
    connect "/hatiwal-cable", params: { access_token: auth["access-token"], client: auth["client"], uid: auth["uid"] }

    expect(connection.current_user).to eq(user)
  end

  # hatiwal-web (src/lib/cable.ts): a browser cannot set WebSocket headers, so it keeps the query
  # string, and the browser adds its own Origin and @rails/actioncable's subprotocols — headers,
  # but not session headers: the query is still read.
  it "connects the web client's exact shape: the query session, with a browser's Origin and subprotocols" do
    connect "/hatiwal-cable?access_token=#{CGI.escape(auth['access-token'])}&client=#{CGI.escape(auth['client'])}&uid=#{CGI.escape(auth['uid'])}",
            headers: { "Origin" => "https://web.example", "Sec-WebSocket-Protocol" => "actioncable-v1-json, actioncable-unsupported" }

    expect(connection.current_user).to eq(user)
  end

  it "headers present but wrong: rejected, even with a valid session in the query (no mixing sources)" do
    expect do
      connect "/hatiwal-cable", headers: { "access-token" => "wrong", "client" => auth["client"], "uid" => auth["uid"] },
                                params: { access_token: auth["access-token"], client: auth["client"], uid: auth["uid"] }
    end.to have_rejected_connection
  end

  it "a session split between the headers and the query is rejected" do
    expect do
      connect "/hatiwal-cable", headers: { "access-token" => auth["access-token"] }, params: { client: auth["client"], uid: auth["uid"] }
    end.to have_rejected_connection
  end

  it "no session anywhere: rejected" do
    expect { connect "/hatiwal-cable" }.to have_rejected_connection
  end

  describe "a single-use ticket (POST /api/v1/cable_ticket; hatiwal-web)" do
    it "connects ONCE, as the user it was issued to; a replay is refused" do
      ticket = CableTicket.issue!(user)
      connect "/hatiwal-cable?ticket=#{ticket}"
      expect(connection.current_user).to eq(user)

      expect { connect "/hatiwal-cable?ticket=#{ticket}" }.to have_rejected_connection
    end

    it "an expired ticket is refused" do
      ticket = CableTicket.issue!(user)
      travel(CableTicket::TTL + 1.second) do
        expect { connect "/hatiwal-cable?ticket=#{ticket}" }.to have_rejected_connection
      end
    end

    it "a ticket binds to its issuer only: with another user's session beside it, refused (no mixing)" do
      other = create(:user).create_new_auth_token
      ticket = CableTicket.issue!(user)
      expect do
        connect "/hatiwal-cable?ticket=#{ticket}", headers: { "access-token" => other["access-token"], "client" => other["client"], "uid" => other["uid"] }
      end.to have_rejected_connection
      expect do
        connect "/hatiwal-cable?ticket=#{ticket}&access_token=x&client=y&uid=z"
      end.to have_rejected_connection
    end

    it "a bad ticket never falls back to anything else" do
      expect { connect "/hatiwal-cable?ticket=nope" }.to have_rejected_connection
    end
  end

  it "the ticket and the legacy session never reach a log: both are filtered parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("ticket" => "t-123", "access_token" => "a", "client" => "c", "uid" => "u@example.com"))
      .to include("ticket" => "[FILTERED]", "access_token" => "[FILTERED]", "uid" => "[FILTERED]")
  end
end
