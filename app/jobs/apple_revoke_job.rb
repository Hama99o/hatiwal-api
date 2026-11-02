# Revokes a deleted account's Apple authorization (Apple::Tokens.revoke). The
# refresh token travels ENCRYPTED in the job's arguments (the queue is a
# database table); a no-op when the Apple key is not configured. Failures are
# logged by Apple::Tokens (Apple keeps no state we could retry against usefully).
class AppleRevokeJob < ApplicationJob
  queue_as :default

  def self.enqueue_for(refresh_token)
    return if refresh_token.blank?

    perform_later(ActiveRecord::Encryption.encryptor.encrypt(refresh_token))
  end

  def perform(encrypted_token)
    Apple::Tokens.revoke(ActiveRecord::Encryption.encryptor.decrypt(encrypted_token))
  end
end
