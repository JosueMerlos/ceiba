# Registers the provisioning hook that enables default modules (idempotent by key across dev reloads).
Rails.application.config.to_prepare { Modules::ProvisioningHook.register }
