class Api::V1::BlocksController < Api::V1::BaseController
  # GET /api/v1/blocks — the users the current user has blocked, newest first.
  def index
    blocked_users = policy_scope(Block)
                    .includes(blocked: { avatar_attachment: :blob })
                    .order(created_at: :desc)
                    .map(&:blocked)

    # One query each for the response stats and listing counts of the whole
    # list (no N+1), and every row here is blocked by definition.
    User.preload_public_stats(blocked_users)
    render_blue_collection(
      UserSerializer, blocked_users,
      view: :public, options: { current_user: current_user, blocked_ids: blocked_users.map(&:id).to_set }
    )
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
