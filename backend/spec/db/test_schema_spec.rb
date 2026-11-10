require "rails_helper"

# When rspec runs with an outdated test schema: with pending migrations the suite ABORTS asking for `make migrate`
# (migrating dumps db/structure.sql, which is versioned; the suite must not silently rewrite it); if only
# db/structure.sql changed, rails_helper reloads the schema with `db:test:prepare` in a subprocess with DB_ROLE=owner and
# carries on with the application connected as app_user.
RSpec.describe "Esquema de test desactualizado" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_test_schema_probe").create }

  after { app.destroy }

  def run_probe = app.run("bundle", "exec", "rspec", "spec/probe_spec.rb")

  before do
    app.db!("db:create", "db:migrate")
    app.write("db/migrate/20261108000003_create_probes.rb", <<~RUBY)
      class CreateProbes < ActiveRecord::Migration[8.1]
        def change
          create_table(:probes, id: :uuid) { |t| t.string :name }
        end
      end
    RUBY
    app.write("spec/probe_spec.rb", <<~RUBY)
      require "rails_helper"
      RSpec.describe "probe" do
        it "ve la tabla nueva y conecta como app_user" do
          connection = ActiveRecord::Base.connection
          expect(connection.table_exists?(:probes)).to be(true)
          expect(connection.select_value("SELECT current_user")).to eq("app_user")
          expect { connection.execute("INSERT INTO probes (name) VALUES ('x')") }.not_to raise_error
        end
      end
    RUBY
  end

  it "aborta con una instrucción clara ante migraciones pendientes, sin tocar db/structure.sql" do
    before_dump = app.read("db/structure.sql")

    output, status = run_probe

    expect(status).not_to be_success
    expect(output).to include("make migrate")
    expect(app.read("db/structure.sql")).to eq(before_dump)
  end

  it "recarga el esquema de test si structure.sql cambió sin migraciones pendientes" do
    app.root.join("db/migrate/20261108000003_create_probes.rb").delete
    app.db!("db:test:prepare")
    structure = app.read("db/structure.sql")
    app.write("db/structure.sql", structure.sub("SET search_path TO", "CREATE TABLE public.probes (id uuid DEFAULT uuidv7() NOT NULL, name character varying);\n\nSET search_path TO"))
    output, status = run_probe

    expect([ status.success?, output[/\d+ examples?, \d+ failures?/] ]).to eq([ true, "1 example, 0 failures" ]), output
  end
end
