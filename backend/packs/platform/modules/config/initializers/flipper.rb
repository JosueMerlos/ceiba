# Flipper con persistencia en la base (flipper-active_record). Sin flags definidos todavía: la infraestructura queda lista y el
# actor es la organización (Modules::FlagActor).
Rails.application.config.to_prepare do
  require "flipper/adapters/active_record"
  Flipper.configure { |config| config.adapter { Flipper::Adapters::ActiveRecord.new } }
  # La instancia por hilo se memoiza con la configuración anterior (la de memoria que trae el railtie): se descarta.
  Flipper.instance = nil
end
