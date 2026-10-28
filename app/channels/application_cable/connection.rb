module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # hatiwal-web (a browser cannot set WebSocket headers): a single-use ticket,
      # and nothing else beside it — a bad one never falls back to a session.
      if request.params.key?(:ticket)
        return reject_unauthorized_connection if session_sent?

        return CableTicket.consume(request.params[:ticket]) || reject_unauthorized_connection
      end

      token, client_id, uid = session_credentials

      return reject_unauthorized_connection unless token.present? && client_id.present? && uid.present?

      user = User.find_by(uid: uid)
      return reject_unauthorized_connection unless user&.valid_token?(token, client_id)

      user
    end

    # The devise_token_auth headers (1.2.0 apps): a URL's query string ends up in
    # proxy access logs, and this session is a login. 1.1.x apps put it in the
    # query; read only when NO session header is sent — never a mix of the two
    # (privacy review 2026-10-28).
    SESSION_HEADERS = %w[access-token client uid].freeze
    SESSION_PARAMS = %i[access_token client uid].freeze

    def session_sent?
      SESSION_HEADERS.any? { |name| request.headers[name].present? } || SESSION_PARAMS.any? { |name| request.params[name].present? }
    end

    def session_credentials
      from_headers = SESSION_HEADERS.map { |name| request.headers[name] }
      return from_headers if from_headers.any?(&:present?)

      SESSION_PARAMS.map { |name| request.params[name] }
    end
  end
end
