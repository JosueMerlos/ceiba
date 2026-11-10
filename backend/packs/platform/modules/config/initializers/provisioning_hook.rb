# Registro del hook de provisión que activa los módulos por defecto (idempotente por key en cada recarga de desarrollo).
Rails.application.config.to_prepare { Modules::ProvisioningHook.register }
