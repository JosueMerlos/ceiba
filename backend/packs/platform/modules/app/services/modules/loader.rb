module Modules
  # Discovers and loads packs/modules/<key>/manifest.rb. Reads FILES: it references no module constants (visible_to: []).
  # Each manifest calls `Modules.define`; while loading, that call goes to the registry being built and its `root` is the
  # manifest's pack.
  class Loader
    KEY = :modules_loader_context

    class << self
      def call(root:, registry:)
        root = Pathname(root)
        root.glob("packs/modules/*/manifest.rb").sort.each { |file| load_manifest(root, file, registry) }
        registry.validate!
      end

      # Registry and pack directory of the load in progress, or nil outside it. Read by Modules.define.
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
