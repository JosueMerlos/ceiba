module Modules
  # Activa un módulo en una empresa (docs/architecture/05-module-system.md): verifica entitlement y `requires`, crea o reactiva la
  # fila, ejecuta `on_enable` y emite platform.module_enabled.v1, todo en una transacción. IDEMPOTENTE: si ya estaba activo no
  # cambia nada (ni hook ni evento) y devuelve `changed: false`. Reactivar (tras desactivar) reutiliza la fila con sus settings.
  #
  #   Tenancy.with_context(organization:) { Modules::Enable.call(company:, key: "appointments") }
  #
  # Lanza Modules::UnknownModule, Modules::NotEntitled o Modules::RequirementsNotMet.
  class Enable < Activation
    def call
      raise NotEntitled, key unless Modules.entitled?(company, key)

      ApplicationRecord.transaction(requires_new: true) do
        row = locked_row
        next result(false) if row&.active?

        ensure_requirements!
        row = activate(row)
        next result(false) unless row

        run_hook(:on_enable, manifest.on_enable)
        publish("platform.module_enabled.v1")
        audit("module.enabled", row, before: false, after: true)
        result(true)
      end
    end

    private

    def ensure_requirements!
      missing = manifest.requires - active_keys
      raise RequirementsNotMet.new(key, missing) if missing.any?
    end

    # Reactiva la fila existente o crea la primera. nil si otra transacción se adelantó (la llamada es una repetición).
    def activate(row)
      return row.tap { row.update!(enabled_at: Time.current, disabled_at: nil) } if row

      create_row
    end

    # Si otra transacción creó la fila entre la lectura y el INSERT, el UNIQUE lo impide: se deja que esa transacción la active
    # (devuelve nil).
    def create_row
      ApplicationRecord.transaction(requires_new: true) do
        CompanyModule.create!(company_id: company.id, module_key: key, enabled_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue ActiveRecord::RecordInvalid => error
      # La validación de unicidad del modelo se adelanta al UNIQUE cuando la otra transacción ya hizo COMMIT.
      raise unless error.record.errors.of_kind?(:module_key, :taken)

      nil
    end
  end
end
