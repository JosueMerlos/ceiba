module Modules
  # Hook de Tenancy::ProvisionOrganization.after_provision: activa en la empresa recién creada los módulos por defecto
  # (`Modules.default_keys`). Corre dentro de la transacción de la provisión y del contexto de la organización nueva: si algo
  # falla (p. ej. una key por defecto que ningún manifiesto declara) se revierte TODA la provisión. Tenancy no conoce a modules;
  # el pack se engancha desde config.to_prepare (config/initializers/provisioning_hook.rb).
  module ProvisioningHook
    KEY = :modules_defaults

    module_function

    def call(result)
      Modules.default_keys.each { |key| Enable.call(company: result.company, key:) }
    end

    # Idempotente por `key:`: se puede llamar en cada recarga.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
