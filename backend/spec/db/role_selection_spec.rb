require "rails_helper"

# Selección de rol FAIL-CLOSED (M0.04): app_user siempre por defecto; app_owner solo con DB_ROLE=owner explícito.
# Las tareas que cambian el esquema se niegan a correr sin DB_ROLE=owner, con un mensaje claro, y db:seed
# se niega a correr como owner. Cada caso corre en un proceso nuevo sobre una copia de la app.
RSpec.describe "Selección del rol de base de datos" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_role_probe").create }
  let(:username_script) { "puts ActiveRecord::Base.connection_db_config.configuration_hash[:username]" }

  after { app.destroy }

  it "usa app_user por defecto" do
    expect(app.rails_runner(username_script)).to eq("app_user")
  end

  it "usa app_user aunque se invoque una tarea db:* (no se infiere el rol del nombre de la tarea)" do
    script = "Rake.application.instance_variable_set(:@top_level_tasks, ['db:migrate']); #{username_script}"

    expect(app.rails_runner(script)).to eq("app_user")
  end

  it "usa app_owner solo con DB_ROLE=owner explícito" do
    output = app.run!("bin/rails", "runner", username_script, env: { "DB_ROLE" => "owner" })

    expect(output.lines.last.strip).to eq("app_owner")
  end

  it "rechaza un DB_ROLE desconocido" do
    output, status = app.run("bin/rails", "runner", username_script, env: { "DB_ROLE" => "admin" })

    expect(status).not_to be_success
    expect(output).to include("DB_ROLE inválido")
  end

  %w[db:create db:drop db:migrate db:rollback db:schema:load db:prepare db:reset db:setup db:test:prepare].each do |task|
    it "#{task} sin DB_ROLE=owner falla con un mensaje claro y sin tocar la base" do
      output, status = app.run("bin/rails", task)

      expect(status).not_to be_success
      expect(output).to include("DB_ROLE=owner").and include("make")
      expect(output).not_to match(/permission denied|PG::/)
    end
  end

  it "db:migrate con DB_ROLE=owner sí corre" do
    app.db!("db:create", "db:migrate")

    expect(app.exist?("db/structure.sql")).to be(true)
  end

  it "db:seed con DB_ROLE=owner falla: se siembra como app_user" do
    app.db!("db:create", "db:migrate")
    output, status = app.run("bin/rails", "db:seed", env: { "DB_ROLE" => "owner" })

    expect(status).not_to be_success
    expect(output).to include("app_user")
  end

  it "db:seed corre como app_user" do
    app.db!("db:create", "db:migrate")
    app.write("db/seeds.rb", "puts \"seed como \#{ActiveRecord::Base.connection.select_value('SELECT current_user')}\"\n")

    expect(app.run!("bin/rails", "db:seed")).to include("seed como app_user")
  end
end
