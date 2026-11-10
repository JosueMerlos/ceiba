require "rails_helper"

# Integration of role selection (config/db_roles.rb + config/initializers/seed_role.rb): each case runs in a new process
# over a copy of the app with its own database.
RSpec.describe "Rol de base de datos por tarea" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_role_probe").create }
  let(:current_user) { "puts ActiveRecord::Base.connection.select_value('SELECT current_user')" }

  after { app.destroy }

  def run_as_seed_probe
    app.write("db/seeds.rb", "puts \"seed como \#{ActiveRecord::Base.connection.select_value('SELECT current_user')}\"\n")
  end

  it "runner usa app_user" do
    app.run!("bin/rails", "db:create", env: { "DB_ROLE" => "owner" })

    expect(app.rails_runner(current_user)).to eq("app_user")
  end

  it "db:migrate (allowlist) corre como app_owner sin DB_ROLE" do
    app.write("db/migrate/20261108000004_say_user.rb", <<~RUBY)
      class SayUser < ActiveRecord::Migration[8.1]
        def change = say("migrado como \#{select_value('SELECT current_user')}")
      end
    RUBY
    app.run!("bin/rails", "db:create")

    expect(app.run!("bin/rails", "db:migrate")).to include("migrado como app_owner")
  end

  it "db:seed corre como app_user" do
    app.db!("db:create", "db:migrate")
    run_as_seed_probe

    expect(app.run!("bin/rails", "db:seed")).to include("seed como app_user")
  end

  %w[db:prepare db:setup].each do |task|
    it "#{task} migra como owner pero siembra como app_user" do
      # The test database is not seeded (seeds: false); here it is enabled in the copy to test the seeds' role.
      app.write("config/database.yml", app.read("config/database.yml").sub("\n  seeds: false", "\n  seeds: true"))
      run_as_seed_probe

      expect(app.run!("bin/rails", task)).to include("seed como app_user")
    end
  end

  it "una tarea propia no listada corre como app_user" do
    app.run!("bin/rails", "db:create")
    app.write("lib/tasks/probe.rake", "task(\"ceiba:whoami\" => :environment) { #{'puts ActiveRecord::Base.connection.select_value("SELECT current_user")'} }\n")

    expect(app.run!("bin/rails", "ceiba:whoami")).to include("app_user")
  end

  it "DB_ROLE=owner fuerza el rol de dueño en cualquier tarea" do
    app.run!("bin/rails", "db:create")
    output = app.run!("bin/rails", "runner", current_user, env: { "DB_ROLE" => "owner" })

    expect(output.lines.last.strip).to eq("app_owner")
  end
end
