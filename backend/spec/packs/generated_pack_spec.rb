require "rails_helper"
require "generators/pack/pack_generator"
require "open3"
require "tmpdir"

# REAL integration test (subprocesses) over a COPY of the application in a temporary directory (nothing is written to
# the repository's packs/): generates a pack and, in a new process, checks that packwerk validates it and Rails/Zeitwerk
# load it (app/*, namespace, eager_load! and db/migrate).
RSpec.describe "Pack generado" do
  def namespace = "GeneratorProbe"
  def migration_version = "20260101000000"

  let(:app_root) { Pathname(Dir.mktmpdir("ceiba-app-copy")) }
  let(:pack_name) { "generator_probe" }
  let(:pack_dir) { app_root.join("packs/modules", pack_name) }
  let(:env) { { "RAILS_ENV" => "test", "RUN_SETUP" => "false", "BUNDLE_GEMFILE" => app_root.join("Gemfile").to_s } }

  def copy_application
    %w[Gemfile Gemfile.lock Rakefile config.ru .ruby-version packwerk.yml package.yml app bin config db lib packs].each do |entry|
      FileUtils.cp_r(Rails.root.join(entry), app_root.join(entry))
    end
    FileUtils.mkdir_p(app_root.join("tmp"))
    FileUtils.mkdir_p(app_root.join("log"))
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def pending_migration_script
    <<~RUBY
      pool = ActiveRecord::Base.connection_pool
      names = pool.migration_context.migrations.map(&:name)
      abort "migration_context no ve la migración del pack: \#{names.inspect}" unless names.include?("CreateProbe")
      begin
        ActiveRecord::Migration.check_all_pending!
        abort "check_all_pending! no detectó la migración pendiente del pack"
      rescue ActiveRecord::PendingMigrationError
        puts "ok"
      end
    RUBY
  end

  def run!(*command)
    Open3.capture2e(env, *command, chdir: app_root.to_s)
  end

  def write_pack_file(relative, content)
    FileUtils.mkdir_p(pack_dir.join(File.dirname(relative)))
    File.write(pack_dir.join(relative), content)
  end

  before do
    copy_application
    silence_stdout { PackGenerator.start([ "modules/#{pack_name}" ], destination_root: app_root.to_s) }
  end

  after { FileUtils.remove_entry(app_root) }

  it "pasa packwerk validate y packwerk check" do
    output, status = run!("bundle", "exec", "packwerk", "validate")
    expect(status).to be_success, output

    output, status = run!("bundle", "exec", "packwerk", "check")
    expect(status).to be_success, output
  end

  it "se carga con Zeitwerk: namespace en app/public y app/models, y eager_load" do
    write_pack_file("app/public/#{pack_name}/probe.rb", "module #{namespace}\n  class Probe; end\nend\n")
    write_pack_file("app/models/#{pack_name}/record.rb", "module #{namespace}\n  class Record; end\nend\n")
    script = <<~RUBY
      Rails.application.eager_load!
      Zeitwerk::Loader.eager_load_all
      abort "namespace no cargado" unless #{namespace}::Probe && #{namespace}::Record
      puts "ok"
    RUBY

    output, status = run!("bin/rails", "runner", script)

    expect([ status.success?, output.lines.last&.strip ]).to eq([ true, "ok" ]), output
  end

  it "registra db/migrate del pack también fuera de rake (migration_context y migraciones pendientes)" do
    write_pack_file("db/migrate/#{migration_version}_create_probe.rb", <<~RUBY)
      class CreateProbe < ActiveRecord::Migration[8.1]
        def change; end
      end
    RUBY
    output, status = run!("bin/rails", "runner", pending_migration_script)

    expect([ status.success?, output.lines.last&.strip ]).to eq([ true, "ok" ]), output
  end
end
