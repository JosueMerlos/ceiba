module Modules
  # Los módulos ACTIVOS de una empresa con sus settings ya resueltos (default -> empresa -> sucursal del contexto), para /me. Dos
  # consultas como máximo (filas de company_modules y overrides de la sucursal), sin importar cuántos módulos haya.
  module ActiveModules
    Entry = Data.define(:manifest, :settings)

    module_function

    def call(company:, branch: nil)
      rows = CompanyModule.active.where(company_id: company.id).to_a
      branch_settings = branch ? BranchModuleSetting.where(branch_id: branch.id).index_by(&:module_key) : {}
      rows.filter_map do |row|
        # Una fila de un módulo cuyo manifiesto ya no existe se ignora (el módulo se retiró del código).
        next unless Modules.registry.key?(row.module_key)

        manifest = Modules.registry.fetch(row.module_key)
        Entry.new(manifest:, settings: SettingsResolver.call!(manifest, row.settings, branch_settings[row.module_key]&.settings))
      end.sort_by { |entry| entry.manifest.key }
    end
  end
end
