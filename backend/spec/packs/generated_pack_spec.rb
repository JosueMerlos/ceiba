require "rails_helper"
require "generators/pack/pack_generator"
require "open3"

# Prueba de integración REAL (subprocesos): genera un pack en packs/, y en un proceso nuevo
# comprueba que packwerk lo valida y que Rails/Zeitwerk lo cargan (app/*, namespace y db/migrate).
# Es el spec de carga que pide M0.03 (Rails.application.eager_load! en CI).
RSpec.describe "Pack generado" do
  let(:pack_name) { "generator_probe" }
  let(:pack_dir) { Rails.root.join("packs/modules", pack_name) }
  let(:namespace) { "GeneratorProbe" }

  def run!(*command)
    output, status = Open3.capture2e({ "RAILS_ENV" => "test", "RUN_SETUP" => "false" }, *command, chdir: Rails.root.to_s)
    [ output, status ]
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  around do |example|
    FileUtils.rm_rf(pack_dir)
    silence_stdout { PackGenerator.start([ "modules/#{pack_name}" ], destination_root: Rails.root.to_s) }
    example.run
  ensure
    FileUtils.rm_rf(pack_dir)
  end

  it "pasa packwerk validate" do
    output, status = run!("bundle", "exec", "packwerk", "validate")

    expect(status).to be_success, output
  end

  it "se carga con Zeitwerk: namespace, db/migrate y eager_load" do
    FileUtils.mkdir_p(pack_dir.join("app/public", pack_name))
    File.write(pack_dir.join("app/public", pack_name, "probe.rb"), "module #{namespace}\n  class Probe; end\nend\n")
    FileUtils.mkdir_p(pack_dir.join("app/models", pack_name))
    File.write(pack_dir.join("app/models", pack_name, "record.rb"), "module #{namespace}\n  class Record; end\nend\n")
    script = <<~RUBY
      Rails.application.eager_load!
      Zeitwerk::Loader.eager_load_all
      abort "namespace no cargado" unless #{namespace}::Probe && #{namespace}::Record
      migrate = Rails.application.paths["db/migrate"].to_a.map { |path| Pathname(path).to_s }
      abort "db/migrate del pack no registrado" unless migrate.include?("#{pack_dir.join('db/migrate')}")
      puts "ok"
    RUBY

    output, status = run!("bin/rails", "runner", script)

    expect([ status.success?, output.lines.last&.strip ]).to eq([ true, "ok" ]), output
  end
end
