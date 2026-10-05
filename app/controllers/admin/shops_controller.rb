# SHOP-1 — admin shops (hatiwal-mobile/docs/SHOPS.md, "Admin"): list + filters,
# the shop page, Suspend / Reactivate, Remove member, Remove badge. Every action
# is written to AdminAuditLog. Verify / Reject live in the verification queue.
module Admin
  class ShopsController < Admin::ApplicationController
    filter :status, :select, options: -> { Shop.statuses.keys }
    filter :verified, :scope, options: -> { %w[yes no] }, scope: lambda { |rel, v|
      v == "yes" ? rel.where.not(verified_at: nil) : rel.where(verified_at: nil)
    }
    # The verification queue for shops: a request is waiting.
    filter :requested, :scope, label: "Verification waiting", options: -> { %w[yes] }, scope: lambda { |rel, v|
      next rel unless v == "yes"

      rel.where(id: VerificationRequest.for_shops.requested.select(:subject_id))
    }
    filter :province, :select, options: -> { ServiceArea::PROVINCE_CAPITALS.keys.sort }
    filter :created, :date_range, column: :created_at, label: "Opened"

    def suspend
      shop = find_resource(params[:id])
      shop.suspend!
      log_admin_action("suspend_shop", target: shop, details: params[:reason].presence)
      redirect_to [ namespace, shop ], notice: "#{shop.name} is suspended: hidden from search, members sell as themselves."
    end

    def reactivate
      shop = find_resource(params[:id])
      shop.reactivate!
      log_admin_action("reactivate_shop", target: shop)
      redirect_to [ namespace, shop ], notice: "#{shop.name} is active again."
    end

    def remove_member
      shop = find_resource(params[:id])
      member = shop.shop_members.find(params[:member_id])
      if shop.remove_member!(member)
        log_admin_action("remove_shop_member", target: shop, details: "user ##{member.user_id} (#{member.role})")
        redirect_to [ namespace, shop ], notice: "Removed #{member.user.full_name} from #{shop.name}."
      else
        redirect_to [ namespace, shop ], alert: "The owner cannot be removed."
      end
    end

    # Take the Verified shop badge off, whether or not an approved request is
    # behind it. The owner gets the reason in their language.
    def remove_badge
      shop = find_resource(params[:id])
      return redirect_to([ namespace, shop ], alert: "#{shop.name} is not verified.") unless shop.verified?

      request = VerificationRequest.revoke_badge!(shop, admin: current_admin_user,
                                                  reason_code: params[:reason_code], reason_text: params[:reason_text])
      log_admin_action("verification_revoke", target: request, details: "shop ##{shop.id} · #{params[:reason_code]}")
      redirect_to [ namespace, shop ], notice: "Badge removed from #{shop.name}. The owner gets a message with the reason."
    rescue ArgumentError => e
      redirect_to [ namespace, shop ], alert: e.message
    end

    private

    # The list renders owner + category for every row: preload them.
    def scoped_resource
      super.includes(:owner, :category)
    end
  end
end
