module Api
  # La cookie de sesión del panel: nombre y atributos en UN solo lugar (docs/architecture/11-security.md).
  #
  # - HttpOnly: el JavaScript de la página no la lee, así un XSS no roba la sesión.
  # - SameSite=Lax: el navegador no la manda en POST/DELETE entre sitios (primera defensa contra CSRF).
  # - Secure y prefijo `__Host-` en producción (config.x.auth.secure_cookies).
  # - Path=/ y sin Domain: es la cookie del origen exacto.
  # - `expires` = caducidad absoluta de la sesión; la inactividad la decide el servidor.
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

    # Para borrar hay que repetir path/secure/same_site: si no, el navegador no la considera "la misma" cookie.
    def clear(cookies) = cookies.delete(name, **attributes)
  end
end
