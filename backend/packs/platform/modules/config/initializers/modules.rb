# Loads and validates manifests at boot and on every code reload: an invalid manifest fails here with a clear message, not on
# the first request.
Rails.application.config.to_prepare { Modules.load! }
