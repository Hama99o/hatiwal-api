require "rails_helper"

# A login must survive a slow or dropped connection, and an active user must
# never be logged out; 2 months away logs out (owner, 2026-10-05).
RSpec.describe "Session stability", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "password123" }
  let!(:user) { create(:user, password: password) }

  def sign_in_headers
    post "/api/v1/auth/sign_in", params: { email: user.email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
    response.headers.slice("access-token", "client", "uid", "token-type")
  end

  def me(headers)
    get "/api/v1/users/me", headers: headers
    response
  end

  it "keeps the same token across requests, so a reply lost in transit can't log the user out" do
    headers = sign_in_headers

    travel 1.minute do
      expect(me(headers)).to have_http_status(:ok)
      # Nothing new to remember: the phone keeps working with what it has.
      expect(response.headers["access-token"].to_s.strip).to be_empty.or eq(headers["access-token"])
    end

    # The reply above "never arrived"; the phone retries with its original
    # token much later and is still signed in.
    travel 2.hours do
      expect(me(headers)).to have_http_status(:ok)
    end
  end

  it "never logs out a user who keeps using the app (sliding 2 months)" do
    headers = sign_in_headers

    # Used every 40 days for 8 months: each use pushes the expiry back.
    1.upto(6) do |i|
      travel_to((40 * i).days.from_now) do
        expect(me(headers)).to have_http_status(:ok)
      end
    end
  end

  it "logs out after 2 months without using the app" do
    headers = sign_in_headers

    travel_to(59.days.from_now) { expect(me(headers)).to have_http_status(:ok) }
    # 59 days later again = 59 days after the last use: still fine.
    travel_to(118.days.from_now) { expect(me(headers)).to have_http_status(:ok) }
    # Then 62 days with no use at all.
    travel_to(180.days.from_now) { expect(me(headers)).to have_http_status(:unauthorized) }
  end

  it "writes the new expiry at most once a day per device" do
    headers = sign_in_headers
    travel_to(2.days.from_now) { me(headers) }

    expect do
      travel_to(2.days.from_now + 3.hours) { me(headers) }
    end.not_to(change { user.reload.updated_at })
  end

  it "extending one device never erases another device's token" do
    phone = sign_in_headers
    stale = User.find(user.id) # this request's copy, loaded before the tablet signs in
    tablet = sign_in_headers

    # The phone's keep-alive runs with its stale copy of the user.
    travel_to(3.days.from_now) do
      controller = Api::V1::BaseController.new
      allow(controller).to receive(:request).and_return(instance_double(ActionDispatch::Request, headers: { "client" => phone["client"] }))
      controller.instance_variable_set(:@resource, stale)
      controller.send(:extend_session_expiry)

      expect(me(tablet)).to have_http_status(:ok)
      expect(me(phone)).to have_http_status(:ok)
    end
  end

  it "signs out the other devices when the password is changed (a leaked token stops working)" do
    stolen = sign_in_headers  # an older session, e.g. a token someone copied
    travel 1.minute
    _owner = sign_in_headers  # the owner's own, newest device
    expect(DeviseTokenAuth.remove_tokens_after_password_reset).to be(true)

    user.reload.update!(password: "newpassword456", password_confirmation: "newpassword456")

    expect(me(stolen)).to have_http_status(:unauthorized)
  end

  it "a signed-in password change keeps the device that made it, even when a leaked token was used more recently" do
    owner = sign_in_headers
    travel 1.minute
    stolen = sign_in_headers # newer AND (keep-alive) the latest expiry: DTA's default would keep THIS one

    put "/api/v1/auth/password", params: { password: "newpassword456", password_confirmation: "newpassword456" },
                                 headers: owner, as: :json
    expect(response).to have_http_status(:ok)

    expect(me(stolen)).to have_http_status(:unauthorized)
    expect(me(owner)).to have_http_status(:ok)
  end

  it "a forgotten-password reset (email link, nobody signed in) signs out every device" do
    phone = sign_in_headers
    raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
    user.update!(reset_password_token: hashed, reset_password_sent_at: Time.current)

    put "/api/v1/auth/password", params: { reset_password_token: raw, password: "newpassword456",
                                           password_confirmation: "newpassword456" }, as: :json
    expect(response).to have_http_status(:ok)

    expect(me(phone)).to have_http_status(:unauthorized)
    post "/api/v1/auth/sign_in", params: { email: user.email, password: "newpassword456" }, as: :json
    expect(response).to have_http_status(:ok)
  end
end
