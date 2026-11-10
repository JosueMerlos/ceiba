require "open3"
require "tmpdir"

# Copy of the app in a temporary directory, with its OWN database, for specs that run real generators, migrations and
# dumps (rails g model, db:migrate, db:structure:dump...) without touching the working tree or the test database. Each
# command runs in a new process (as in CI or in a console).
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

  # Runs a command in the copy; returns [output, status].
  def run(*command, env: {})
    Open3.capture2e(base_env.merge(env), *command, chdir: root.to_s)
  end

  def run!(*command, **options)
    output, status = run(*command, **options)
    raise "#{command.join(' ')} falló:\n#{output}" unless status.success?

    output
  end

  # Schema tasks (db:*): the config/db_roles.rb allowlist runs them as app_owner.
  def db!(*tasks) = run!("bin/rails", *tasks)

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
