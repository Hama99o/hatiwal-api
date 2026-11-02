# OFFLINE §10.6 — a seller list asks for the identity it is cached under
# (`selling_as`: "me" | a shop id) instead of the server's current "selling as":
# a sell-as switch queued offline must not file one identity's rows under the
# other's key. No `selling_as` (1.1.x apps): the server's current identity.
module SellingIdentityParam
  extend ActiveSupport::Concern

  private

  # [:ok, shop_or_nil] or [:unavailable] (a shop the user may not see).
  def requested_selling_identity
    return [ :ok, current_user.selling_shop ] unless params.key?(:selling_as)

    current_user.identity_for(params[:selling_as] == "me" ? nil : params[:selling_as])
  end

  def render_shop_unavailable
    render_unprocessable_entity(I18n.t("shops.errors.cannot_sell_as"), code: :shop_unavailable)
  end
end
