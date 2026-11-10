module Modules
  # Desactiva un módulo en una empresa: marca `disabled_at`, ejecuta `on_disable` y emite platform.module_disabled.v1, en una
  # transacción. NO borra datos (la fila, los settings y los de sus sucursales se conservan: reactivar los recupera). IDEMPOTENTE.
  # No deja desactivar un módulo que otro módulo ACTIVO de la empresa requiere (Modules::RequiredByOthers).
  class Disable < Activation
    def call
      ApplicationRecord.transaction(requires_new: true) do
        lock_company!
        row = locked_row
        next result(false) unless row&.active?

        ensure_not_required!
        row.update!(disabled_at: Time.current)
        run_hook(:on_disable, manifest.on_disable)
        publish("platform.module_disabled.v1")
        audit("module.disabled", row, before: true, after: false)
        result(true)
      end
    end

    private

    def ensure_not_required!
      dependents = Modules.registry.requirers_of(key).map(&:key) & active_keys
      raise RequiredByOthers.new(key, dependents) if dependents.any?
    end
  end
end
