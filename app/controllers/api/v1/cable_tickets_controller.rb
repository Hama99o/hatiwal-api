# POST /api/v1/cable_ticket — a single-use pass for the cable's connect URL
# (`?ticket=…`, one connect within CableTicket::TTL), for clients that cannot set
# WebSocket headers: hatiwal-web. The 1.2.0 app sends its session in the
# upgrade headers instead. ApplicationCable::Connection consumes the ticket.
class Api::V1::CableTicketsController < Api::V1::BaseController
  # A reconnect asks for a new one: generous, but not a mint.
  throttle to: 120, within: 1.hour, by: :user, only: :create

  def create
    authorize CableTicket
    response.set_header("Cache-Control", "no-store")
    render_ok({ ticket: CableTicket.issue!(current_user), expires_in: CableTicket::TTL.to_i }, status: :created)
  end
end
