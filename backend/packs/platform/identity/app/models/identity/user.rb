module Identity
  # Persona que inicia sesión. GLOBAL, no tenant (ADR-0028): una misma persona puede pertenecer a varias organizaciones
  # y esa pertenencia vive en los memberships (M0.08), no aquí. Por eso `users` no tiene organization_id.
  class User < ApplicationRecord
    # Mínimo de OWASP/NIST: longitud, sin reglas de complejidad ni rotación forzada (docs/architecture/11-security.md).
    # El rechazo contra HIBP llega en M4.02.
    MINIMUM_PASSWORD_LENGTH = 12

    has_secure_password

    has_many :sessions, dependent: :restrict_with_exception

    normalizes :email, with: ->(email) { email.strip.downcase }

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true },
      uniqueness: { case_sensitive: false }
    validates :full_name, presence: true
    validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  end
end
