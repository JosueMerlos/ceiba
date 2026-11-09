require "rails_helper"

# El registro descubre los manifiestos por ARCHIVO (packs/modules/*/manifest.rb), sin referenciar constantes de ningún módulo
# (visible_to: [], docs/architecture/02-modular-monolith.md). Al arrancar los carga, los valida y registra sus permisos en access.
RSpec.describe "Carga de manifiestos" do
  def write_manifest(root, pack, body)
    path = root.join("packs/modules/#{pack}")
    FileUtils.mkdir_p(path)
    File.write(path.join("manifest.rb"), body)
  end

  let(:root) { Pathname(Dir.mktmpdir) }

  after { FileUtils.remove_entry(root) }

  describe Modules::Loader do
    it "carga cada packs/modules/<key>/manifest.rb y devuelve el registro validado" do
      write_manifest(root, "alfa", %(Modules.define(:alfa, root: __dir__) { name "Alfa"; version "1.0" }))
      write_manifest(root, "beta", %(Modules.define(:beta, root: __dir__) { name "Beta"; version "1.0"; requires %i[alfa] }))

      registry = described_class.call(root: root, registry: Modules::Registry.new)

      expect(registry.keys).to contain_exactly("alfa", "beta")
    end

    it "falla con el mensaje del manifiesto inválido (así falla el arranque, criterio 1)" do
      write_manifest(root, "alfa", <<~RUBY)
        Modules.define(:alfa, root: __dir__) do
          name "Alfa"
          version "1.0"
          permissions { permission "beta.cosa.leer", description: "Ajeno" }
        end
      RUBY

      expect { described_class.call(root: root, registry: Modules::Registry.new) }
        .to raise_error(Modules::InvalidManifest, /alfa.*"beta\.cosa\.leer".*debe empezar por "alfa\."/m)
    end

    it "falla si el manifiesto no define el módulo de su carpeta (la key es estable y coincide con el pack)" do
      write_manifest(root, "alfa", %(Modules.define(:otro, root: __dir__) { name "Otro"; version "1.0" }))

      expect { described_class.call(root: root, registry: Modules::Registry.new) }
        .to raise_error(Modules::InvalidManifest, /packs\/modules\/alfa.*define "otro".*"alfa"/m)
    end

    it "falla si el manifiesto no define nada" do
      write_manifest(root, "alfa", "# vacío")

      expect { described_class.call(root: root, registry: Modules::Registry.new) }
        .to raise_error(Modules::InvalidManifest, /alfa.*no define/m)
    end

    it "valida los requires entre manifiestos una vez cargados todos" do
      write_manifest(root, "alfa", %(Modules.define(:alfa, root: __dir__) { name "Alfa"; version "1.0"; requires %i[beta] }))
      write_manifest(root, "beta", %(Modules.define(:beta, root: __dir__) { name "Beta"; version "1.0"; requires %i[alfa] }))

      expect { described_class.call(root: root, registry: Modules::Registry.new) }.to raise_error(Modules::InvalidManifest, /ciclo/)
    end

    it "sin packs/modules devuelve un registro vacío" do
      expect(described_class.call(root: root, registry: Modules::Registry.new).keys).to be_empty
    end
  end

  describe "el registro de la aplicación (cargado al arrancar)" do
    it "tiene a appointments, descubierto por archivo" do
      expect(Modules.registry.fetch("appointments")).to have_attributes(key: "appointments", name: "Citas")
    end

    it "registró los permisos del manifiesto en access, con los roles de sus concesiones" do
      expect(Access.registered?("appointments.appointment.read")).to be(true)
      definition = Access.registry.fetch("appointments.appointment.update_own")

      expect(definition).to have_attributes(module_key: "appointments", roles: %w[professional])
    end
  end
end
