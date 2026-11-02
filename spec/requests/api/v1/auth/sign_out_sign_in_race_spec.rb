require "rails_helper"

# P0 login race (d0, 2026-10-06): a 200 sign-in came back WITHOUT auth headers.
# Cause: DTA's sign_out loads the user at the start of the request, then deletes
# its client from that in-memory copy and saves the whole `tokens` hash. When the
# app signs out (client A) and signs the SAME user back in (client B) at once,
# the sign-out's stale save wipes B, and the sign-in's after_action finds no B.
# A sign-out must remove only its own client from the CURRENT tokens.
RSpec.describe "Sign-out racing a sign-in of the same user", type: :request do
  let(:user) { create(:user) }

  def sign_in_headers
    post "/api/v1/auth/sign_in", params: { email: user.email, password: "password123" }, as: :json
    expect(response).to have_http_status(:ok)
    response.headers.slice("access-token", "client", "uid")
  end

  it "a sign-out that loaded the user before a concurrent sign-in keeps the new session" do
    old = sign_in_headers
    new_client = nil

    # Run the concurrent sign-in exactly between the sign-out loading the user
    # and the sign-out saving it: the window the race needs.
    allow_any_instance_of(Api::V1::Auth::SessionsController).to receive(:set_user_by_token).and_wrap_original do |original, *args|
      loaded = original.call(*args)
      concurrent = User.find(user.id)
      new_client = concurrent.create_new_auth_token["client"]
      loaded
    end

    delete "/api/v1/auth/sign_out", headers: old
    expect(response).to have_http_status(:ok)

    tokens = user.reload.tokens
    expect(tokens).not_to have_key(old["client"])
    expect(tokens).to have_key(new_client)
  end

  it "a plain sign-in always carries the new session's headers, and they work" do
    headers = sign_in_headers
    expect(headers.values).to all(be_present)
    get "/api/v1/users/me", headers: headers
    expect(response).to have_http_status(:ok)
  end

  it "a sign-in that carries an older session's headers still returns the NEW session's headers" do
    old = sign_in_headers
    post "/api/v1/auth/sign_in", params: { email: user.email, password: "password123" }.to_json,
                                 headers: old.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(response.headers["access-token"]).to be_present
    expect(response.headers["client"]).to be_present
    expect(response.headers["client"]).not_to eq(old["client"])
  end
end
