# Registers the organization owner hook (idempotent by key across development reloads).
Rails.application.config.to_prepare { Access::OwnerHook.register }
