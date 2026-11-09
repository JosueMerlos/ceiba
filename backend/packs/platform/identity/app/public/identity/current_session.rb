module Identity
  # La sesión que presenta una request: resuelve el token de la cookie y expone lo que el resto de la aplicación puede
  # saber de ella (el principal, el token CSRF, su caducidad) sin filtrar el modelo `Session`.
  class CurrentSession
    CSRF_KEY_PURPOSE = "ceiba/identity/csrf".freeze

    attr_reader :principal

    # Devuelve la sesión activa de ese token o nil (ausente, desconocida, revocada, vencida por inactividad o por
    # vigencia absoluta). Registra la actividad con throttle de 1 minuto.
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

    # Token CSRF ligado a ESTA sesión: HMAC-SHA256(clave derivada de secret_key_base, id de la sesión). Sin estado en BD;
    # cambia cuando la sesión rota (login) y no sirve con otra sesión. No contiene el token de la cookie.
    def csrf_token
      OpenSSL::HMAC.hexdigest("SHA256", self.class.csrf_key, @session.id)
    end

    def valid_csrf_token?(candidate)
      candidate.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(candidate, csrf_token)
    end

    def revoke!(now: Time.current) = @session.revoke!(now:)

    # "Cerrar sesión en todos los dispositivos".
    def revoke_all!(now: Time.current) = Session.revoke_all_for(@session.user, now:)

    def self.csrf_key = Rails.application.key_generator.generate_key(CSRF_KEY_PURPOSE, 32)
  end
end
