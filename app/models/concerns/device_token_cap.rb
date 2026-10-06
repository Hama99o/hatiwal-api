# P0 (2026-10-06): past max_number_of_devices tokens, devise_token_auth's
# clean_old_tokens drops every token expiring after `now + token_lifespan.to_i`.
# Tokens stamped with a calendar lifespan (61 days from Oct 6) were over that
# line, the one being issued included: the user was signed out everywhere and the
# sign-in answered 200 with no auth headers. token_lifespan is now a fixed length
# (config/initializers/devise_token_auth.rb), but tokens already issued keep their
# calendar expiry, so the cap is enforced here instead: keep the token being
# issued, then the newest others by expiry, up to the limit. Nothing is dropped
# for having a "future" expiry.
#
# Prepended: devise_token_auth defines create_token on the class itself.
module DeviceTokenCap
  def create_token(client: nil, **options)
    @issuing_token_client = client || SecureRandom.urlsafe_base64(nil, false)
    super(client: @issuing_token_client, **options)
  ensure
    @issuing_token_client = nil
  end

  private

  def clean_old_tokens
    return if tokens.blank? || !max_client_tokens_exceeded?

    issuing = @issuing_token_client if @issuing_token_client && tokens.key?(@issuing_token_client)
    others = tokens.except(issuing).sort_by { |_client, t| (t[:expiry] || t["expiry"]).to_i }
    kept = others.last(DeviseTokenAuth.max_number_of_devices - (issuing ? 1 : 0)).to_h
    kept[issuing] = tokens[issuing] if issuing
    self.tokens = kept
  end
end
