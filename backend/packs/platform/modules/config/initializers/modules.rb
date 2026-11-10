# Carga y valida los manifiestos al arrancar y tras cada recarga de código (docs/architecture/05-module-system.md): un
# manifiesto inválido falla aquí, con un mensaje claro, no en la primera request.
Rails.application.config.to_prepare { Modules.load! }
