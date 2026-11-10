module Modules
  # Descubre y carga los manifiestos de packs/modules/<key>/manifest.rb. Lee ARCHIVOS: no referencia constantes de ningún
  # módulo (visible_to: [], docs/architecture/02-modular-monolith.md). Cada manifiesto llama a `Modules.define`; mientras se
  # carga, esa llamada va al registro que se está construyendo y su `root` es el pack del manifiesto.
  class Loader
    KEY = :modules_loader_context

    class << self
      def call(root:, registry:)
        root = Pathname(root)
        root.glob("packs/modules/*/manifest.rb").sort.each { |file| load_manifest(root, file, registry) }
        registry.validate!
      end

      # Contexto de la carga en curso (registro y directorio del pack) o nil fuera de ella. Lo lee Modules.define.
      def current = Thread.current[KEY]

      private

      def load_manifest(root, file, registry)
        pack = file.dirname.basename.to_s
        relative = file.relative_path_from(root)
        before = registry.keys
        with_context(registry:, root: file.dirname) { Kernel.load(file.to_s) }
        defined = registry.keys - before
        raise InvalidManifest.new(pack, [ "#{relative} no define ningún módulo (debe llamar a Modules.define :#{pack})" ]) if defined.empty?
        return if defined == [ pack ]

        raise InvalidManifest.new(pack, [ "#{relative} define #{defined.map(&:inspect).join(', ')} pero debe definir #{pack.inspect} (la key coincide con el nombre del pack)" ])
      end

      def with_context(**context)
        previous = Thread.current[KEY]
        Thread.current[KEY] = context
        yield
      ensure
        Thread.current[KEY] = previous
      end
    end
  end
end
