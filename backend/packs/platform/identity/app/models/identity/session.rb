module Identity
  # Sesión del panel respaldada en BD (ADR-0017). Se revoca desde el servidor sin desplegar (11-security).
  #
  # - El token es aleatorio (256 bits) y SOLO existe en claro en la cookie del navegador y en `session.token` justo tras
  #   emitirla; la BD guarda su digest SHA-256. Un volcado de la tabla no permite suplantar a nadie. SHA-256 (y no
  #   bcrypt) basta porque el token tiene entropía de sobra: no hay nada que adivinar por fuerza bruta.
  # - Vigencia: inactividad (IDLE_TIMEOUT) y absoluta (ABSOLUTE_LIFETIME, no se extiende con la actividad).
  class Session < ApplicationRecord
    IDLE_TIMEOUT = 12.hours
    ABSOLUTE_LIFETIME = 7.days
    # `last_seen_at` se escribe como máximo una vez por minuto y sesión: no hay un UPDATE por request.
    TOUCH_INTERVAL = 1.minute
    USER_AGENT_LIMIT = 255

    belongs_to :user

    attr_reader :token

    scope :active, lambda { |now = Time.current|
      where(revoked_at: nil).where("expires_at > ?", now).where("last_seen_at > ?", now - IDLE_TIMEOUT)
    }

    def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

    # Crea la sesión y devuelve el registro; `session.token` es el único momento en que el token existe en claro.
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
