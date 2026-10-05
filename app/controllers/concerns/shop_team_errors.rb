# SHOP-3 — every team endpoint answers its refusals with the codes in
# docs/SHOPS.md ("Errors"), so the apps can show their own sentence.
module ShopTeamErrors
  extend ActiveSupport::Concern

  included do
    rescue_from ShopInvite::Refused do |e|
      render_coded_error(e.message, code: e.code, status: e.status)
    end
    # A member calling an owner action is `forbidden`; someone outside the shop
    # is `not_a_member`. Both 403.
    rescue_from Pundit::NotAuthorizedError do |_e|
      code = @shop&.member?(current_user) ? :forbidden : :not_a_member
      render_coded_error(I18n.t("shops.team.errors.#{code}"), code: code, status: :forbidden)
    end
  end
end
