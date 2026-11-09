# API pública del pack platform/modules (ADR-0010, docs/architecture/05-module-system.md). Los módulos de negocio se
# DECLARAN con `Modules.define` desde su `manifest.rb`; la plataforma los descubre por archivo (no referencia sus constantes).
module Modules
  class << self
    # Declara un módulo. Se llama desde `packs/modules/<key>/manifest.rb`: durante la carga (Modules.load!) va al registro que
    # se está construyendo y toma el pack como `root`; fuera de ella (los specs, p. ej. el módulo `sample`) va al registro global
    # y registra sus permisos en access. Valida el manifiesto: si algo está mal lanza Modules::InvalidManifest.
    def define(key, root: nil, &block)
      loading = Loader.current
      return loading[:registry].define(key, root: root || loading[:root], &block) if loading

      registry.define(key, root:, &block).tap { |manifest| AccessRegistration.call(manifest) }
    end

    # Registro global de la aplicación.
    def registry = @registry ||= Registry.new

    # ¿Está el módulo ACTIVO en la empresa? Una consulta. `company` es la empresa (o su id), dentro de Tenancy.with_context.
    def enabled?(company, key)
      CompanyModule.active.exists?(company_id: company.respond_to?(:id) ? company.id : company, module_key: key.to_s)
    end

    # Settings RESUELTOS y validados de un módulo: default del esquema -> empresa -> sucursal (si se da `branch`). El módulo debe estar
    # activo en la empresa (Modules::NotEnabled); lo guardado que ya no cumpla el esquema lanza Modules::InvalidSettings.
    # Dentro de Tenancy.with_context. Devuelve un Hash nuevo. Escribir: Modules::UpdateSettings.
    def settings_for(key, company:, branch: nil)
      raise ArgumentError, "la sucursal #{branch.id} no es de la empresa #{company.id}" if branch && branch.company_id != company.id

      manifest = registry.fetch(key)
      company_row = CompanyModule.active.find_by(company_id: company.id, module_key: manifest.key) or raise NotEnabled, manifest.key
      branch_settings = branch && BranchModuleSetting.find_by(branch_id: branch.id, module_key: manifest.key)&.settings
      SettingsResolver.call!(manifest, company_row.settings, branch_settings)
    end

    # ¿Permite el plan de la organización este módulo? (entitlement: docs/architecture/05-module-system.md, "Tres conceptos").
    # TODO(F6): consultar plans/plan_entitlements cuando existan (docs/roadmap/README.md, F6 — Producto vendible). Hasta entonces
    # todos los planes tienen entitlement a todo (sin límites): activar solo exige `requires`.
    def entitled?(_company, _key) = true

    # Carga y valida todos los manifiestos de packs/modules y registra sus permisos en access. Corre al arrancar (y en cada
    # recarga de código, config/initializers/modules.rb): un manifiesto inválido FALLA el arranque con un mensaje claro.
    def load!(root: Rails.root)
      fresh = Loader.call(root:, registry: Registry.new)
      fresh.each { |manifest| AccessRegistration.call(manifest) }
      Access.module_gate = AccessGate
      @registry = fresh
    end
  end
end
