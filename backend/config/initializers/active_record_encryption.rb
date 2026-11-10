# Active Record Encryption keys are NOT stored in the repository:
#   - development and test: DERIVED from secret_key_base via key_generator, so they are stable while that secret is.
#   - production and staging (RAILS_ENV=production): read from the environment. If missing they stay nil and `encrypts`
#     FAILS on use (ActiveRecord::Encryption::Errors::Configuration): fail closed, never with a default key.
#       AR_ENCRYPTION_PRIMARY_KEY, AR_ENCRYPTION_DETERMINISTIC_KEY, AR_ENCRYPTION_KEY_DERIVATION_SALT (random strings of
#       32+ bytes; `bin/rails db:encryption:init` generates them).
module EncryptionKeys
  ENV_NAMES = {
    primary_key: "AR_ENCRYPTION_PRIMARY_KEY",
    deterministic_key: "AR_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "AR_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  def self.for(production:, env:, key_generator:)
    ENV_NAMES.to_h do |name, variable|
      value = production ? env[variable].presence : key_generator.generate_key("ceiba/active_record_encryption/#{name}", 32).unpack1("H*")
      [ name, value ]
    end
  end
end

keys = EncryptionKeys.for(production: Rails.env.production?, env: ENV, key_generator: Rails.application.key_generator)
Rails.application.config.active_record.encryption.merge!(keys.compact)
