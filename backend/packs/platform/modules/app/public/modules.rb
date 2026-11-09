# API pública del pack platform/modules (ADR-0010, docs/architecture/05-module-system.md). Los módulos de negocio se
# DECLARAN con `Modules.define` desde su `manifest.rb`; la plataforma los descubre por archivo (no referencia sus constantes).
module Modules
  class << self
    # Declara un módulo en el registro global y registra sus permisos en access. Se llama desde `packs/modules/<key>/manifest.rb`
    # (el cargador pasa `root:`); valida el manifiesto y falla el arranque con un mensaje claro si no cumple 05.
    def define(key, root: nil, &block) = registry.define(key, root:, &block)

    def registry = @registry ||= Registry.new
  end
end
