# Public, no-login unsubscribe from BULK email (docs/EMAIL.md).
#
#   GET  /unsubscribe/:token        the page, in the user's language, one button
#   POST /unsubscribe/:token        opt out — also what a mail client sends for
#                                   one-click (RFC 8058: body "List-Unsubscribe=One-Click")
#   POST /unsubscribe/:token/undo   opt back in (a forwarded email shouldn't be
#                                   able to opt someone out with no way back)
#
# The token is a signed user id; nothing else identifies anyone. The POST is
# CSRF-exempt by necessity — a mail client's one-click POST carries no token —
# and is safe to repeat (it only sets a timestamp if absent).
class UnsubscribesController < ActionController::Base
  protect_from_forgery with: :exception, except: :create
  layout false

  before_action :set_user

  def show; end

  def create
    @user.update_columns(email_opt_out_at: Time.current) if @user.email_opt_out_at.nil?
    render :show
  end

  def undo
    @user.update_columns(email_opt_out_at: nil)
    @undone = true
    render :show
  end

  private

  def set_user
    @user = User.find_signed(params[:token], purpose: User::UNSUBSCRIBE_PURPOSE)
    @locale = @user&.preferred_language.presence_in(User::SUPPORTED_LANGUAGES) || "en"
    render :invalid, status: :not_found unless @user
  end
end
