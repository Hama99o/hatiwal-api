class Api::V1::BlocksController < Api::V1::BaseController
  # Hunt-2 (1.1.7): block/unblock toggling notifies and rewrites feeds.
  throttle to: 60, within: 1.hour, by: :user, only: %i[create destroy]

  # GET /api/v1/blocks — the users the current user has blocked, newest first.
  def index
    blocks = policy_scope(Block)
             .includes(blocked: { avatar_attachment: :blob }, shop: { logo_attachment: :blob })
             .order(created_at: :desc).to_a
    blocked_users = blocks.map(&:blocked)

    # One query each for the response stats and listing counts of the whole
    # list (no N+1), and every row here is blocked by definition.
    User.preload_public_stats(blocked_users)
    people = UserSerializer.render_as_hash(blocked_users, view: :public,
                                                          current_user: current_user, blocked_ids: blocked_users.map(&:id).to_set)
    # privacy-b: a block made from a shop lists the SHOP (unblocked with
    # DELETE /shops/:id/block), never its owner. Pre-1.1.6 clients, which can
    # only unblock by user id, keep the person.
    rows = blocks.zip(people).map do |block, person|
      shop = block.shop
      next person if shop.nil? || shop.closed? || Current.legacy_shop_ids

      { id: nil, shop_id: shop.id, as_shop: true, name: shop.name, avatar_url: shop.logo_url,
        city: shop.city.presence || shop.province, verified: shop.verified?, blocked: true }
    end
    render_ok({ UserSerializer.model_name.plural => rows })
  end

  def create
    user_to_block = User.find(params[:user_id])
    authorize Block.new(blocker: current_user, blocked: user_to_block)
    current_user.blocked_users << user_to_block unless current_user.blocked?(user_to_block)
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  def destroy
    user_to_unblock = User.find(params[:user_id])
    authorize Block.new(blocker: current_user, blocked: user_to_unblock)
    current_user.blocked_users.delete(user_to_unblock)
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end
end
