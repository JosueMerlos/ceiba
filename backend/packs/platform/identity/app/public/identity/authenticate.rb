module Identity
  # Email and password sign-in.
  #
  #   result = Identity::Authenticate.call(email:, password:, ip:, user_agent:, previous_token: cookie)
  #   result.token            # plain-text token: goes in the cookie and is stored nowhere else
  #   result.current_session  # Identity::CurrentSession
  #
  # - Raises Identity::InvalidCredentials for an unknown email or a wrong password (same class, same message).
  # - Constant time: `authenticate_by` computes bcrypt even when the account does not exist, so the response time does
  #   not reveal whether the email has an account.
  # - Rotation: login ALWAYS issues a new token and revokes the session the browser carried (even another user's), so a
  #   token fixed before login is useless afterwards (session fixation).
  class Authenticate
    Result = Data.define(:token, :current_session)

    def self.call(...) = new(...).call

    def initialize(email:, password:, ip: nil, user_agent: nil, previous_token: nil, now: Time.current)
      @email = email.to_s
      @password = password.to_s
      @ip = ip
      @user_agent = user_agent
      @previous_token = previous_token
      @now = now
    end

    def call
      user = User.authenticate_by(email: @email, password: @password)
      reject_credentials! unless user

      session = Session.transaction do
        Session.find_active_by_token(@previous_token, now: @now)&.revoke!(now: @now)
        Session.issue!(user:, ip: @ip, user_agent: @user_agent, now: @now).tap { |issued| audit_success(user, issued) }
      end
      Result.new(token: session.token, current_session: CurrentSession.new(session))
    end

    private

    def audit_success(user, session)
      Audit.record_auth(action: "auth.login_succeeded", user_id: user.id, ip: @ip, user_agent: @user_agent, metadata: { session_id: session.id })
    end

    # Audits the attempt and rejects it. The account is ALWAYS looked up (whether it exists or not) so both failures do
    # the same work. An HMAC pseudonym of the email is stored (Audit.pseudonymize; never the email or password): it
    # correlates attempts without retaining the email or a secret typed by mistake in that field. Written outside any
    # transaction, so it survives the 401.
    def reject_credentials!
      normalized = User.normalize_value_for(:email, @email)
      Audit.record_auth(
        action: "auth.login_failed", user_id: User.where(email: normalized).pick(:id), ip: @ip, user_agent: @user_agent,
        metadata: { email_digest: Audit.pseudonymize(normalized) }
      )
      raise InvalidCredentials, "Credenciales inválidas"
    end
  end
end
