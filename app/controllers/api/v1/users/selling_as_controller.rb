# SHOP-1 — PATCH /api/v1/users/me/selling_as  { shop_id: <id> | null }
#
# Who the user sells as in Seller mode ("Selling as"). Saved on the server so it
# survives app restarts and a second phone (users.active_shop_id). null = Me.
# A shop the user is not an active member of is refused (422) and nothing changes.
class Api::V1::Users::SellingAsController < Api::V1::BaseController
  def update
    authorize current_user, :update_selling_as?
    shop = params[:shop_id].present? ? Shop.find_by(id: params[:shop_id]) : nil
    refused = (params[:shop_id].present? && shop.nil?) || !current_user.sell_as!(shop)
    return render_unprocessable_entity(I18n.t("shops.errors.cannot_sell_as"), code: :cannot_sell_as_shop) if refused

    render_blue(UserSerializer, current_user.reload, view: :me)
  end
end
