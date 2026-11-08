require "rails_helper"

# Al correr rspec con el esquema de test desactualizado (migración nueva, structure.sql distinto) la suite lo
# prepara sola: rails_helper lanza `db:prepare` como subproceso con DB_ROLE=owner, acotado a ese subproceso, y
# después sigue con la aplicación conectada como app_user.
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

  it "migra el esquema de test con el rol de dueño y corre la suite como app_user" do
    output, status = run_probe

    expect([ status.success?, output[/\d+ examples?, \d+ failures?/] ]).to eq([ true, "1 example, 0 failures" ]), output
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
