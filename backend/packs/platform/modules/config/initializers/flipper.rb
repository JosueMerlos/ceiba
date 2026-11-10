# Flipper con persistencia en la base (flipper-active_record). Sin flags definidos todavía: la infraestructura queda lista y el
# actor es la organización (Modules::FlagActor).
# Sin flags definidos, no tiene sentido precargarlos todos en CADA request (ni en /api/health): el Memoizer de Flipper los leería de la
# base. Se activa cuando existan flags (y entonces con una lista de rutas, no global).
Rails.application.config.flipper.preload = false

Rails.application.config.to_prepare do
  require "flipper/adapters/active_record"
  Flipper.configure { |config| config.adapter { Flipper::Adapters::ActiveRecord.new } }
  # La instancia por hilo se memoiza con la configuración anterior (la de memoria que trae el railtie): se descarta.
  Flipper.instance = nil
end
