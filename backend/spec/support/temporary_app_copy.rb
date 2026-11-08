require "open3"
require "tmpdir"

# Copia de la app en un directorio temporal, con su PROPIA base de datos, para specs que ejecutan generadores,
# migraciones y volcados reales (rails g model, db:migrate, db:structure:dump...) sin tocar el árbol de trabajo
# ni la base de test. Cada comando corre en un proceso nuevo (como en CI o en consola).
class TemporaryAppCopy
  ENTRIES = %w[Gemfile Gemfile.lock Rakefile config.ru .ruby-version .rspec packwerk.yml package.yml app bin config db lib packs spec].freeze

  attr_reader :root, :database

  def initialize(database:)
    @database = database
    @root = Pathname(Dir.mktmpdir("ceiba-app-copy"))
  end

  def create
    ENTRIES.each { |entry| FileUtils.cp_r(Rails.root.join(entry), root.join(entry)) }
    FileUtils.mkdir_p(root.join("tmp"))
    FileUtils.mkdir_p(root.join("log"))
    database_yml = root.join("config/database.yml")
    database_yml.write(database_yml.read.gsub("ceiba_test", database))
    self
  end

  # Ejecuta un comando en la copia; devuelve [salida, estado].
  def run(*command, env: {})
    Open3.capture2e(base_env.merge(env), *command, chdir: root.to_s)
  end

  def run!(*command, **options)
    output, status = run(*command, **options)
    raise "#{command.join(' ')} falló:\n#{output}" unless status.success?

    output
  end

  # Tareas de esquema (db:*): requieren DB_ROLE=owner explícito (fail-closed, ver config/database.yml).
  def db!(*tasks) = run!("bin/rails", *tasks, env: { "DB_ROLE" => "owner" })

  def rails_runner(script) = run!("bin/rails", "runner", script).lines.last.to_s.strip

  def write(relative, content)
    FileUtils.mkdir_p(root.join(File.dirname(relative)))
    root.join(relative).write(content)
  end

  def read(relative) = root.join(relative).read

  def exist?(relative) = root.join(relative).exist?

  def destroy
    run("bin/rails", "db:drop", env: { "DB_ROLE" => "owner" }) if root.exist?
    FileUtils.remove_entry(root) if root.exist?
  end

  private

  def base_env
    { "RAILS_ENV" => "test", "RUN_SETUP" => "false", "BUNDLE_GEMFILE" => root.join("Gemfile").to_s }
  end
end
