module Identity
  # The session a request presents: resolves the cookie's token and exposes what the rest of the app may know about it
  # (principal, CSRF token, expiry) without leaking the `Session` model.
  class CurrentSession
    CSRF_KEY_PURPOSE = "ceiba/identity/csrf".freeze

    attr_reader :principal

    # Returns the token's active session or nil (absent, unknown, revoked, idle-expired or past its absolute lifetime).
    # Records activity throttled to 1 minute.
    def self.resolve(token, now: Time.current)
      session = Session.includes(:user).find_active_by_token(token, now:)
      return unless session

      session.touch_activity!(now:)
      new(session)
    end

    def initialize(session)
      @session = session
      user = session.user
      @principal = Principal::User.new(id: user.id, email: user.email, full_name: user.full_name)
    end

    def expires_at = @session.expires_at

    # CSRF token bound to THIS session: HMAC-SHA256(key derived from secret_key_base, session id). Stateless; it changes
    # when the session rotates (login) and is useless with another session. It does not contain the cookie token.
    def csrf_token
      OpenSSL::HMAC.hexdigest("SHA256", self.class.csrf_key, @session.id)
    end

    def valid_csrf_token?(candidate)
      candidate.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(candidate, csrf_token)
    end

    def revoke!(now: Time.current)
      Session.transaction do
        @session.revoke!(now:)
        Audit.record_auth(action: "auth.logout", user_id: @session.user_id, metadata: { session_id: @session.id })
      end
    end

    def revoke_all!(now: Time.current)
      Session.transaction do
        count = Session.revoke_all_for(@session.user, now:)
        Audit.record_auth(action: "auth.sessions_revoked", user_id: @session.user_id, metadata: { count: })
      end
    end

    def self.csrf_key = Rails.application.key_generator.generate_key(CSRF_KEY_PURPOSE, 32)
  end
end
