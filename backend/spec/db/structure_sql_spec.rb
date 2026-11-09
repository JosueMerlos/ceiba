require "rails_helper"

# Criterio 6 de M0.04: db/structure.sql, cargado en una BD vacía, incluye extensiones, políticas y FKs compuestas.
# Se prueba sobre una copia de la app con las migraciones reales (organizations/companies/branches, M0.05) más una
# tabla de sonda con exclusion constraint y citext, y su propia base: migrar, volcar, volcar de nuevo (determinismo), revertir/migrar y cargar en una BD vacía.
RSpec.describe "db/structure.sql" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_structure_probe").create }

  after { app.destroy }

  before do
    app.write("db/migrate/20261109000001_create_probe_tables.rb", <<~RUBY)
      class CreateProbeTables < ActiveRecord::Migration[8.1]
        def change
          create_tenant_table :probe_slots do |t|
            t.tenant_reference :company
            t.citext :code, null: false
            t.tstzrange :blocks
            t.exclusion_constraint "organization_id WITH =, blocks WITH &&", using: :gist, name: "probe_slots_no_overlap"
          end
        end
      end
    RUBY
    app.db!("db:create", "db:migrate")
  end

  def structure = app.read("db/structure.sql")

  it "incluye las extensiones" do
    expect(structure).to include("CREATE EXTENSION IF NOT EXISTS btree_gist", "CREATE EXTENSION IF NOT EXISTS citext")
  end

  it "incluye las políticas tenant_isolation" do
    expect(structure).to include("CREATE POLICY tenant_isolation ON public.probe_slots", "CREATE POLICY tenant_isolation ON public.companies")
  end

  it "incluye las FKs compuestas y las UNIQUE (organization_id, id)" do
    expect(structure).to include("FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id)", "UNIQUE (organization_id, id)")
  end

  it "usa uuidv7() como default de las PK y no deja RLS activado" do
    expect(structure).to include("id uuid DEFAULT uuidv7() NOT NULL")
    expect(structure).not_to include("ENABLE ROW LEVEL SECURITY")
  end

  it "no depende del entorno: sin propietarios, privilegios, tokens aleatorios ni extensiones de diagnóstico" do
    expect(structure).not_to match(/\\restrict|OWNER TO|pg_stat_statements|GRANT /)
  end

  it "es determinista: volcar dos veces da el mismo archivo" do
    first = structure
    app.db!("db:schema:dump")

    expect(structure).to eq(first)
  end

  it "migrar, revertir la última y volver a migrar no cambia el archivo" do
    first = structure
    app.db!("db:rollback")
    app.db!("db:migrate")

    expect(structure).to eq(first)
  end

  it "se carga en una BD vacía con extensiones, políticas y FKs compuestas" do
    app.db!("db:drop", "db:create", "db:schema:load")
    report = app.rails_runner(<<~RUBY)
      c = ActiveRecord::Base.connection
      extensions = c.select_values("SELECT extname FROM pg_extension").sort & %w[btree_gist citext]
      policies = c.select_values("SELECT tablename FROM pg_policies WHERE policyname = 'tenant_isolation' ORDER BY 1")
      composite = c.select_value("SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND conrelid = 'probe_slots'::regclass AND array_length(conkey, 1) = 2")
      puts [extensions.join(","), policies.join(","), composite, c.select_value("SELECT current_user")].join(" ")
    RUBY

    expect(report).to eq("btree_gist,citext audit_events,branch_module_settings,branches,companies,company_modules,idempotency_keys,memberships,outbox_events,probe_slots,processed_events 1 app_user")
  end

  it "las tablas cargadas desde structure.sql pertenecen a app_owner y app_user puede usarlas" do
    app.db!("db:drop", "db:create", "db:schema:load")
    report = app.rails_runner(<<~RUBY)
      c = ActiveRecord::Base.connection
      owners = c.select_values("SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname = 'public'")
      org = c.select_value("INSERT INTO organizations (name, created_at, updated_at) VALUES ('o', now(), now()) RETURNING id")
      puts [owners.join(","), org.present?].join(" ")
    RUBY

    expect(report).to eq("app_owner true")
  end
end
