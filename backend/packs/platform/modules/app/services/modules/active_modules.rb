module Modules
  # Los módulos ACTIVOS de una empresa con sus settings ya resueltos (default -> empresa -> sucursal del contexto), para /me. Dos
  # consultas como máximo (filas de company_modules y overrides de la sucursal), sin importar cuántos módulos haya.
  module ActiveModules
    Entry = Data.define(:manifest, :settings)

    # Lo guardado puede dejar de cumplir el esquema (un cambio incompatible, un dato corrupto). /me no debe romperse por UN módulo:
    # se degrada a los defaults del esquema (el módulo sigue activo) y se REPORTA para corregir el dato.
    # Degradación gradual: un override de SUCURSAL inválido cae al nivel de empresa (la empresa conserva lo suyo); si la empresa
    # tampoco es válida, a los defaults del esquema.
    def resolve(manifest, row, branch_row)
      SettingsResolver.call!(manifest, row.settings, branch_row&.settings)
    rescue InvalidSettings => error
      report(error, manifest, row, branch_row)
      branch_row ? resolve(manifest, row, nil) : manifest.defaults.deep_dup
    end

    def report(error, manifest, row, branch_row)
      context = { module: manifest.key, company_id: row.company_id, branch_id: branch_row&.branch_id }.compact
      Rails.error.report(error, handled: true, severity: :error, context:)
    end
    module_function :resolve, :report
    private_class_method :resolve, :report

    module_function

    def call(company:, branch: nil)
      rows = CompanyModule.active.where(company_id: company.id).to_a
      branch_settings = branch ? BranchModuleSetting.where(branch_id: branch.id).index_by(&:module_key) : {}
      rows.filter_map do |row|
        # Una fila de un módulo cuyo manifiesto ya no existe se ignora (el módulo se retiró del código).
        next unless Modules.registry.key?(row.module_key)

        manifest = Modules.registry.fetch(row.module_key)
        Entry.new(manifest:, settings: resolve(manifest, row, branch_settings[row.module_key]))
      end.sort_by { |entry| entry.manifest.key }
    end
  end
end
