require "rails_helper"

# Privacy review 2026-10-28: the cable session used to ride in the URL's query
# string (?access_token=…&client=…&uid=<email>), and every proxy in front of the
# API may log request URLs. 1.2.0 apps send the devise_token_auth HEADERS
# instead; 1.1.x apps still send the query and keep working.
RSpec.describe ApplicationCable::Connection, type: :channel do
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
end
