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

    # Carga y valida todos los manifiestos de packs/modules y registra sus permisos en access. Corre al arrancar (y en cada
    # recarga de código, config/initializers/modules.rb): un manifiesto inválido FALLA el arranque con un mensaje claro.
    def load!(root: Rails.root)
      fresh = Loader.call(root:, registry: Registry.new)
      fresh.each { |manifest| AccessRegistration.call(manifest) }
      @registry = fresh
    end
  end
end
