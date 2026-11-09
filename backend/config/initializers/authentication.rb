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
