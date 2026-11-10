module Identity
  # Person who signs in. GLOBAL, not tenant: one person may belong to several organizations and that membership lives in
  # memberships, not here. Hence `users` has no organization_id.
  class User < ApplicationRecord
    # OWASP/NIST minimum: length, with no complexity rules or forced rotation.
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
