# Sentry (M0.13). Debe inicializarse en un initializer: sentry-rails registra su suscriptor de Rails.error al terminar el
# arranque, leyendo esta configuración. Ver config/middleware/sentry_setup.rb.
require Rails.root.join("config/middleware/sentry_setup").to_s

SentrySetup.init
