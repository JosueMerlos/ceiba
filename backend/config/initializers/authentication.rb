# Autenticación del panel (M0.07, docs/architecture/11-security.md).
#
# Rails en modo API (`config.api_only`) NO trae el middleware de cookies: sin él, `cookies[...] = ...` no emite ningún
# Set-Cookie y la sesión nunca llegaría al navegador. Se incluye de forma explícita (y lo comprueba
# spec/config/authentication_config_spec.rb). Sesión y flash de Rails siguen fuera: la sesión es nuestra, en BD.
Rails.application.config.middleware.use ActionDispatch::Cookies

# Cookie `Secure` y prefijo `__Host-` (Secure + Path=/ + sin Domain: el navegador no deja que un subdominio la pise).
# Solo con HTTPS: producción y staging (RAILS_ENV=production, ADR-0013). En desarrollo y test se sirve por HTTP.
Rails.application.config.x.auth.secure_cookies = Rails.env.production?

# Active Storage monta rutas propias (subidas directas) que no pasan por Api::BaseController, es decir, quedarían
# abiertas sin sesión. Ningún hito usa archivos todavía (branding llega más tarde): sus rutas se dibujan cuando haya
# un hito que las necesite, con autenticación (spec/requests/api/authentication_spec.rb lo vigila).
Rails.application.config.active_storage.draw_routes = false

# Orígenes desde los que el navegador puede mutar (validación de Origin/Referer, Api::Authentication). Lista EXPLÍCITA:
# no se deriva de Host ni de X-Forwarded-Host, que un cliente que llega directo al puerto de la app puede falsificar.
#   APP_ORIGINS  orígenes separados por comas (p. ej. "https://app.ceiba.example"). Obligatoria en producción y staging.
#   desarrollo   http://localhost:<PUBLIC_PORT|8080> (el proxy de compose.yaml)
#   test         http://www.example.com (el host de los request specs)
# Sin valor en producción la lista queda VACÍA y toda mutación con Origin se rechaza (falla cerrado, nunca abierto).
# `config.hosts` (rechazo de Host desconocidos) llega con M0.13/M4.04.
Rails.application.config.x.auth.allowed_origins =
  if ENV["APP_ORIGINS"].present?
    ENV["APP_ORIGINS"].split(",").map { |origin| origin.strip.delete_suffix("/").downcase }.compact_blank
  elsif Rails.env.test?
    [ "http://www.example.com" ]
  elsif Rails.env.development?
    [ "http://localhost:#{ENV.fetch('PUBLIC_PORT', '8080')}" ]
  else
    []
  end
