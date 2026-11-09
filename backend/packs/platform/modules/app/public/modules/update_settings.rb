module Modules
  # Escribe los settings de un módulo en una empresa o, con `branch:`, en una sucursal (docs/architecture/05-module-system.md).
  # Cada valor se valida contra el JSON Schema del módulo; un valor inválido, una clave que el esquema no define o una clave que
  # no se permite a nivel sucursal lanza Modules::InvalidSettings con el detalle por campo (422 en la API) y NO guarda nada.
  #
  #   Modules::UpdateSettings.call(company:, key: "appointments", settings: { "min_lead_time_minutes" => 60 }, branch:)
  #
  # `settings` son SOLO las claves a cambiar (se combinan con los overrides anteriores del mismo nivel); un valor `nil` quita el
  # override y vuelve al del nivel superior. Devuelve los settings resueltos de ese nivel. Exige el módulo activo (NotEnabled).
  class UpdateSettings
    def self.call(company:, key:, settings:, branch: nil) = new(company:, key:, settings:, branch:).call

    def initialize(company:, key:, settings:, branch:)
      raise ArgumentError, "settings debe ser un Hash (recibió #{settings.class})" unless settings.respond_to?(:to_h) && !settings.is_a?(Array)
      raise ArgumentError, "la sucursal #{branch.id} no es de la empresa #{company.id}" if branch && branch.company_id != company.id

      @company = company
      @branch = branch
      @manifest = Modules.registry.fetch(key)
      @changes = settings.to_h.stringify_keys
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        company_row = CompanyModule.active.lock.find_by(company_id: @company.id, module_key: @manifest.key)
        raise NotEnabled, @manifest.key unless company_row

        reject_unknown_or_not_allowed!
        @branch ? update_branch(company_row) : update_company(company_row)
      end
    end

    private

    def update_company(row)
      overrides = merge(row.settings)
      resolved = SettingsResolver.call!(@manifest, overrides)
      row.update!(settings: overrides)
      audit
      resolved
    end

    def update_branch(company_row)
      row = BranchModuleSetting.lock.find_or_initialize_by(branch_id: @branch.id, module_key: @manifest.key)
      overrides = merge(row.settings)
      resolved = SettingsResolver.call!(@manifest, company_row.settings, overrides)
      row.update!(company_id: @company.id, settings: overrides)
      audit
      resolved
    end

    def merge(current) = current.merge(@changes).compact

    def reject_unknown_or_not_allowed!
      errors = @changes.each_key.filter_map do |name|
        if @manifest.setting_keys.exclude?(name)
          error(name, "unknown")
        elsif @branch && !@manifest.overridable_at?(:branch, name)
          error(name, "not_allowed_at_level")
        end
      end
      raise InvalidSettings.new(@manifest.key, errors) if errors.any?
    end

    def error(field, code) = { field:, code:, message: I18n.t("modules.settings_errors.#{code}") }

    # TODO(M0.11): auditar el cambio de settings con Audit.record (actor, empresa, sucursal, módulo, claves) en esta transacción.
    def audit; end
  end
end
