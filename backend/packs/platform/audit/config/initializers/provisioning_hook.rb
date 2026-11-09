# Registro del hook de provisión (idempotente por key en cada recarga de desarrollo).
Rails.application.config.to_prepare { Audit::ProvisioningHook.register }
