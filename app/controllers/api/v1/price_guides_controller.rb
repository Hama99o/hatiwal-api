# IDEA-4 (docs/PRICE_GUIDE.md): the price range of similar sold items for a
# subcategory + currency. Public; one precomputed row; only aggregates. A buyer
# ask (`audience=buyer`) is answered only when the server enables it.
class Api::V1::PriceGuidesController < Api::V1::BaseController
  skip_before_action :authenticate_user!, only: [ :show ]

  def show
    authorize PriceGuide, :show?
    guide = PriceGuide.find_by(category_id: params[:category_id], currency: params[:currency].to_s.upcase)
    hidden_for_buyer = params[:audience] == "buyer" && !PriceGuide.buyers_enabled?
    expires_in 1.hour, public: true
    render_ok({ price_guide: guide && !hidden_for_buyer ? guide.payload : { available: false } })
  end
end
