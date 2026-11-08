require "rails_helper"
require "generators/pack/pack_generator"
require "tmpdir"

RSpec.describe PackGenerator do
  let(:destination) { Dir.mktmpdir("ceiba-pack-generator") }

  after { FileUtils.remove_entry(destination) }

  def run_generator(path)
    generator = described_class.new([ path ], {}, destination_root: destination)
    generator.shell = Thor::Shell::Basic.new
    allow(generator.shell).to receive(:say_status)
    allow(generator.shell).to receive(:say)
    generator.invoke_all
  end

  def pack_file(path, relative)
    Pathname(destination).join("packs", path, relative)
  end

  context "con un módulo (modules/foo)" do
    before { run_generator("modules/foo") }

    it "crea la estructura documentada en 02-modular-monolith" do
      %w[
        app/public/foo app/models/foo app/services/foo app/controllers/api/v1/foo app/policies/foo
        app/serializers/foo app/jobs/foo app/subscribers/foo db/migrate
      ].each { |dir| expect(pack_file("modules/foo", dir)).to be_directory, "falta #{dir}" }
    end

    it "declara la capa, las dependencias, la privacidad y las capas en package.yml" do
      package = YAML.safe_load_file(pack_file("modules/foo", "package.yml"))

      expect(package).to include(
        "layer" => "modules", "enforce_dependencies" => true, "enforce_privacy" => true, "enforce_layers" => true
      )
    end

    it "depende del pack raíz y de ningún otro" do
      package = YAML.safe_load_file(pack_file("modules/foo", "package.yml"))

      expect(package["dependencies"]).to eq([ "." ])
    end

    it "crea un manifest.rb placeholder" do
      expect(pack_file("modules/foo", "manifest.rb").read).to include("foo").and include("M0.09")
    end

    it "crea el archivo de locales es-NI con la raíz del pack" do
      locale = YAML.safe_load_file(pack_file("modules/foo", "config/locales/es-NI.yml"))

      expect(locale).to eq("es-NI" => { "foo" => {} })
    end

    it "crea un spec base que verifica el contrato del pack" do
      spec = pack_file("modules/foo", "spec/package_spec.rb").read

      expect(spec).to include('it_behaves_like "un pack del monolito modular"').and include('layer: "modules"')
    end
  end

  context "con un pack de plataforma (platform/bar_baz)" do
    before { run_generator("platform/bar_baz") }

    it "declara la capa platform y no crea manifest.rb" do
      package = YAML.safe_load_file(pack_file("platform/bar_baz", "package.yml"))

      expect(package).to include("layer" => "platform", "enforce_layers" => true)
      expect(pack_file("platform/bar_baz", "manifest.rb")).not_to exist
    end

    it "no crea carpetas exclusivas de los módulos" do
      expect(pack_file("platform/bar_baz", "app/public/bar_baz")).to be_directory
      expect(pack_file("platform/bar_baz", "app/subscribers/bar_baz")).to be_directory
    end
  end

  describe "validaciones" do
    it "rechaza una capa inválida" do
      expect { run_generator("core/foo") }.to raise_error(Thor::Error, /capa.*platform.*modules/m)
    end

    it "rechaza una ruta sin capa" do
      expect { run_generator("foo") }.to raise_error(Thor::Error, /<capa>\/<nombre>/)
    end

    it "rechaza una ruta con más de dos segmentos" do
      expect { run_generator("modules/foo/bar") }.to raise_error(Thor::Error, /<capa>\/<nombre>/)
    end

    %w[Foo foo-bar 1foo foo.bar FOO].each do |name|
      it "rechaza el nombre inválido #{name.inspect}" do
        expect { run_generator("modules/#{name}") }.to raise_error(Thor::Error, /snake_case/)
      end
    end

    it "rechaza un nombre reservado por Ruby o Rails" do
      expect { run_generator("modules/class") }.to raise_error(Thor::Error, /reservado/)
    end

    it "no sobrescribe un pack existente" do
      run_generator("modules/foo")

      expect { run_generator("modules/foo") }.to raise_error(Thor::Error, /ya existe/)
    end

    it "no permite el mismo nombre en otra capa (los namespaces son únicos)" do
      run_generator("platform/foo")

      expect { run_generator("modules/foo") }.to raise_error(Thor::Error, /namespace/)
    end
  end
end
