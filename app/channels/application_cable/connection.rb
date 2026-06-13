module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      token      = request.params[:access_token]
      client_id  = request.params[:client]
      uid        = request.params[:uid]

      return reject_unauthorized_connection unless token.present? && client_id.present? && uid.present?

      user = User.find_by(email: uid)
      return reject_unauthorized_connection unless user&.valid_token?(token, client_id)

      user
    end
  end
end
