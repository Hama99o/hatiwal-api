class Api::V1::BlocksController < Api::V1::BaseController
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
