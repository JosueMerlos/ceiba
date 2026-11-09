# Registro del hook del dueño de la organización (idempotente por key en cada recarga de desarrollo).
Rails.application.config.to_prepare { Access::OwnerHook.register }
