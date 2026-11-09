# Active Record Encryption (M0.11: idempotency_keys.response_body; la PII del cliente final llega con customers).
#
# Las claves NO viven en el repositorio:
#   - desarrollo y test: se DERIVAN de secret_key_base con key_generator (como el token CSRF y el cursor): son estables
#     mientras no cambie esa secreta y no hay que gestionar nada.
#   - producción y staging (RAILS_ENV=production): vienen del entorno. Si faltan, quedan en nil y `encrypts` FALLA al usar
#     (ActiveRecord::Encryption::Errors::Configuration): falla cerrado, nunca con una clave por defecto.
#       AR_ENCRYPTION_PRIMARY_KEY, AR_ENCRYPTION_DETERMINISTIC_KEY, AR_ENCRYPTION_KEY_DERIVATION_SALT  (cadenas aleatorias de 32+ bytes;
#       por ejemplo `bin/rails db:encryption:init` las genera). Rotarlas: docs/architecture/09-data-conventions.md.
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
