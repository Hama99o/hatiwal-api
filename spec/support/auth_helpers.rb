module AuthHelpers
  def auth_headers_for(user)
    post "/api/v1/auth/sign_in", params: { email: user.email, password: user.password }, as: :json
    {
      "access-token" => response.headers["access-token"],
      "token-type"   => response.headers["token-type"],
      "client"       => response.headers["client"],
      "uid"          => response.headers["uid"]
    }
  end
end
