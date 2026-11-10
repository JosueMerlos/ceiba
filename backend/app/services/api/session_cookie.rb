module Api
  # The panel session cookie: name and attributes in ONE place.
  #
  # - HttpOnly: page JavaScript cannot read it, so an XSS cannot steal the session.
  # - SameSite=Lax: the browser does not send it on cross-site POST/DELETE (first CSRF defense).
  # - Secure and `__Host-` prefix in production (config.x.auth.secure_cookies).
  # - Path=/ and no Domain: it is the exact origin's cookie.
  # - `expires` = absolute session expiry; inactivity is decided by the server.
  module SessionCookie
    BASE_NAME = "ceiba_session".freeze
    HOST_PREFIX = "__Host-".freeze

    module_function

    def secure? = Rails.configuration.x.auth.secure_cookies

    def name = secure? ? "#{HOST_PREFIX}#{BASE_NAME}" : BASE_NAME

    def attributes
      { httponly: true, secure: secure?, same_site: :lax, path: "/" }
    end

    def write(cookies, token, expires_at:)
      cookies[name] = attributes.merge(value: token, expires: expires_at)
    end

    # To delete, path/secure/same_site must be repeated: otherwise the browser does not treat it as the "same" cookie.
    def clear(cookies) = cookies.delete(name, **attributes)
  end
end
