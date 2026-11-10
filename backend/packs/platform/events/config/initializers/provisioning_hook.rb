# Idempotent by key, so every development reload can register it again.
Rails.application.config.to_prepare { Events::ProvisioningHook.register }
