# IDEA-8 (1.2.1, hatiwal-mobile docs/design/SHARE_AND_QR.md §3.5): the printable QR card (ShareCard).
#
#   GET /api/v1/shops/:id/qr_card.png|pdf?lang=ps      a shop's card
#   GET /api/v1/listings/:id/qr_card.png|pdf?lang=fa   a listing's card
#   ...&download=1                                     sent as an attachment (the web's "Save image")
#
# Public data, like the pages the QR opens: no sign-in. 404 for what is not public (a closed,
# suspended or pending shop; a listing that is not live, removed or from a hidden seller). Cached by
# the client and any proxy for a day (ETag = the record's version + language + ShareCard::VERSION),
# and in Rails.cache on the server.
class Api::V1::QrCardsController < Api::V1::BaseController
  # Generous: carrier-grade NAT puts a whole city behind one address (RateLimitable).
  PER_IP_PER_HOUR = 600
  FORMATS = { "png" => "image/png", "pdf" => "application/pdf" }.freeze

  skip_before_action :authenticate_user!
  throttle to: PER_IP_PER_HOUR, within: 1.hour, by: :ip

  def shop
    shop = Shop.find(params[:id])
    raise ActiveRecord::RecordNotFound unless shop.available_to_buyers?

    authorize shop, :qr_card?
    send_card(shop, "shop")
  end

  def listing
    listing = Listing.browsable.find(params[:id])
    authorize listing, :qr_card?
    send_card(listing, "listing")
  end

  private

  def send_card(record, kind)
    format = params[:format].to_s
    lang = ShareCard.card_lang(params[:lang])
    expires_in 1.day, public: true
    return unless stale?(etag: [ record.cache_key_with_version, lang, format, ShareCard::VERSION ], public: true)

    bytes = Rails.cache.fetch([ "share_card", ShareCard::VERSION, record.cache_key_with_version, lang, format ], expires_in: 1.week) do
      format == "pdf" ? ShareCard.pdf(record, lang: lang) : ShareCard.png(record, lang: lang)
    end
    # ?download=1: a browser saves the file (the web's "Save image"; a cross-origin <a download> is ignored).
    disposition = params[:download].present? ? "attachment" : "inline"
    send_data bytes, type: FORMATS.fetch(format), disposition: disposition, filename: "hatiwal-#{kind}-#{record.id}-#{lang}.#{format}"
  end
end
