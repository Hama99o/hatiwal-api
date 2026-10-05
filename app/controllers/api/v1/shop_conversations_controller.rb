# SHOP-2 — POST /api/v1/shops/:shop_id/conversations { message? }
# "Message shop" from the shop page: the caller's one chat with the shop that
# has no product. 201 when it is created, 200 with the same chat after.
# (hatiwal-mobile/docs/SHOPS.md, "Phase 2 — definition of done")
class Api::V1::ShopConversationsController < Api::V1::BaseController
  # Same budget as starting a chat about a listing: this reaches a stranger's inbox.
  throttle to: 30, within: 1.day, by: :user, only: :create

  def create
    shop = Shop.find(params[:shop_id])
    return render_not_found unless shop.active?

    authorize shop, :message?
    service = Conversations::StartShopService.new(buyer: current_user, shop: shop, message_body: params[:message])
    conversation = service.call
    render_blue(ConversationSerializer, conversation, view: :detailed, status: service.created ? :created : :ok,
                                                      options: { current_user: current_user })
  rescue Conversations::StartShopService::Error => e
    render_unprocessable_entity(e, code: e.code)
  end
end
