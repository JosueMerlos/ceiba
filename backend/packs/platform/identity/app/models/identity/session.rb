module Identity
  # Panel session backed by the DB. It is revoked from the server without deploying.
  #
  # - The token is random (256 bits) and exists in plain text ONLY in the browser cookie and in `session.token` right
  #   after issuing it; the DB stores its SHA-256 digest. A table dump cannot impersonate anyone. SHA-256 (not bcrypt)
  #   suffices because the token has ample entropy: there is nothing to brute-force.
  # - Lifetime: idle (IDLE_TIMEOUT) and absolute (ABSOLUTE_LIFETIME, not extended by activity).
  class Session < ApplicationRecord
    IDLE_TIMEOUT = 12.hours
    ABSOLUTE_LIFETIME = 7.days
    # `last_seen_at` is written at most once per minute per session: no UPDATE on every request.
    TOUCH_INTERVAL = 1.minute
    USER_AGENT_LIMIT = 255

    belongs_to :user

    attr_reader :token

    scope :active, lambda { |now = Time.current|
      where(revoked_at: nil).where("expires_at > ?", now).where("last_seen_at > ?", now - IDLE_TIMEOUT)
    }

    def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

    # Creates the session and returns the record; `session.token` is the only moment the token exists in plain text.
    def self.issue!(user:, ip: nil, user_agent: nil, now: Time.current)
      token = SecureRandom.urlsafe_base64(32)
      create!(
        user:, token_digest: digest(token), ip:, user_agent: user_agent&.truncate(USER_AGENT_LIMIT, omission: ""),
        last_seen_at: now, expires_at: now + ABSOLUTE_LIFETIME
      ).tap { |session| session.instance_variable_set(:@token, token) }
    end

    def self.find_active_by_token(token, now: Time.current)
      return if token.blank?

      active(now).find_by(token_digest: digest(token))
    end

    def self.revoke_all_for(user, now: Time.current)
      where(user_id: user.id, revoked_at: nil).update_all(revoked_at: now, updated_at: now)
    end

    def touch_activity!(now: Time.current)
      return if last_seen_at > now - TOUCH_INTERVAL

      update_columns(last_seen_at: now, updated_at: now)
    end

    def revoke!(now: Time.current)
      return if revoked_at

      update_columns(revoked_at: now, updated_at: now)
    end
  end
end
