require "rails_helper"

# With an empty DB, `bin/rails db:seed` twice leaves exactly the 2 demo organizations. Runs on a copy of the app with its
# own database (as app_user, the seeds' role) and in new processes.
RSpec.describe "db/seeds.rb" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_seeds_probe").create }
  let(:demo_customers) do
    [ [ "Carmen Altamirano", "+50588000003" ], [ "Marlon Gutiérrez", "+50588000001" ], [ "Yahaira Ruiz", "+50588000002" ] ]
  end
  let(:expected_census) do
    [
      [ "Barbería El Güegüense", [
        [ "NIO", "barbershop", 1,
          [ [ "Corte clásico", 30, 20_000, "NIO" ], [ "Corte y barba", 45, 30_000, "NIO" ], [ "Afeitado clásico", 30, 15_000, "NIO" ] ],
          [], demo_customers, barbershop_staff ]
      ] ],
      [ "Café Volcán", [ [ "NIO", "cafe", 1, [], [], demo_customers, empty_staff ] ] ],
      [ "Grupo Salud & Estilo", [
        [ "USD", "dental", 1,
          [ [ "Limpieza dental", 45, 4_000, "USD" ], [ "Consulta de valoración", 30, 2_500, "USD" ], [ "Blanqueamiento dental", 60, 12_000, "USD" ] ],
          [], demo_customers, dental_staff ],
        [ "NIO", "salon", 2,
          [ [ "Corte de dama", 45, 25_000, "NIO" ], [ "Tinte completo", 120, 80_000, "NIO" ], [ "Manicure", 40, 18_000, "NIO" ], [ "Peinado de evento", 60, 35_000, "NIO" ] ],
          [ [ "Estilo Altamira", "Corte de dama", nil, 28_000 ] ], demo_customers, salon_staff ]
      ] ]
    ]
  end

  # A company without a catalog (the café) gets no professionals and no resources; its branch still gets the default hours.
  def empty_staff
    { "professionals" => [], "resources" => [], "requirements" => [], "branch_slots" => [ [ "Sede Granada", 6 ] ], "professional_slots" => [], "resource_slots" => [], "time_offs" => 0 }
  end
  def barbershop_staff
    {
      "professionals" => [
        [ "Don Efraín Blandón", true, [ "Sucursal Centro" ], [ "Afeitado clásico", "Corte clásico", "Corte y barba" ] ],
        [ "Ramiro Salinas", false, [ "Sucursal Centro" ], [ "Afeitado clásico", "Corte clásico" ] ]
      ],
      "resources" => [ [ "Sucursal Centro", "Silla 1", "chair" ], [ "Sucursal Centro", "Silla 2", "chair" ] ],
      "requirements" => [ [ "Corte clásico", "chair" ], [ "Corte y barba", "chair" ] ],
      "branch_slots" => [ [ "Sucursal Centro", 6 ] ],
      "professional_slots" => [ [ "Don Efraín Blandón", "Sucursal Centro", [ 1, 2, 3, 4, 5, 6 ] ], [ "Ramiro Salinas", "Sucursal Centro", [ 2, 3, 4, 5, 6 ] ] ],
      "resource_slots" => [],
      "time_offs" => 1
    }
  end
  def dental_staff
    {
      "professionals" => [
        [ "Dr. Pablo Quintana", false, [ "Clínica Sonrisa Central" ], [ "Blanqueamiento dental", "Consulta de valoración", "Limpieza dental" ] ],
        [ "Sandra Gómez", true, [ "Clínica Sonrisa Central" ], [ "Consulta de valoración", "Limpieza dental" ] ]
      ],
      "resources" => [ [ "Clínica Sonrisa Central", "Sala de blanqueamiento", "room" ], [ "Clínica Sonrisa Central", "Sillón 1", "chair" ] ],
      "requirements" => [ [ "Blanqueamiento dental", "room" ], [ "Limpieza dental", "chair" ] ],
      "branch_slots" => [ [ "Clínica Sonrisa Central", 6 ] ],
      "professional_slots" => [ [ "Dr. Pablo Quintana", "Clínica Sonrisa Central", [ 1, 2, 3, 4, 5 ] ], [ "Sandra Gómez", "Clínica Sonrisa Central", [ 2, 4 ] ] ],
      "resource_slots" => [ [ "Sala de blanqueamiento", 5 ] ],
      "time_offs" => 1
    }
  end
  def salon_staff
    {
      "professionals" => [
        [ "Karla Mendieta", false, [ "Estilo Altamira" ], [ "Corte de dama", "Manicure", "Peinado de evento", "Tinte completo" ] ],
        [ "Sandra Gómez", true, [ "Estilo Centro" ], [ "Corte de dama", "Manicure", "Peinado de evento" ] ]
      ],
      "resources" => [ [ "Estilo Altamira", "Sillón 1", "chair" ], [ "Estilo Centro", "Sillón 1", "chair" ], [ "Estilo Centro", "Sillón 2", "chair" ] ],
      "requirements" => [ [ "Corte de dama", "chair" ], [ "Tinte completo", "chair" ] ],
      "branch_slots" => [ [ "Estilo Altamira", 6 ], [ "Estilo Centro", 6 ] ],
      "professional_slots" => [ [ "Karla Mendieta", "Estilo Altamira", [ 2, 4, 6 ] ], [ "Sandra Gómez", "Estilo Centro", [ 1, 3, 5 ] ] ],
      "resource_slots" => [],
      "time_offs" => 1
    }
  end


  before { app.db!("db:create", "db:migrate") }

  after { app.destroy }

  def census
    app.rails_runner(<<~RUBY)
      report = Tenancy::Organization.order(:name).map do |organization|
        Tenancy.with_context(organization:) do
          companies = Tenancy::Company.order(:slug).map do |c|
            services = Appointments::Service.where(company_id: c.id).order(:position).pluck(:name, :duration_minutes, :price_minor, :currency)
            overrides = Appointments::BranchServiceOverride.where(company_id: c.id).map do |o|
              [ Tenancy::Branch.find(o.branch_id).name, Appointments::Service.find(o.service_id).name, o.duration_minutes, o.price_minor ]
            end
            customers = Customers::Customer.where(company_id: c.id).order(:full_name).pluck(:full_name, :phone_e164)
            branch_names = Tenancy::Branch.where(company_id: c.id).pluck(:id, :name).to_h
            professionals = Appointments::Professional.where(company_id: c.id).order(:display_name).map do |p|
              [ p.display_name, !p.user_id.nil?, p.branch_assignments.map { branch_names.fetch(it.branch_id) }.sort,
                Appointments::Service.where(id: p.professional_services.map(&:service_id)).pluck(:name).sort ]
            end
            resources = Appointments::Resource.where(company_id: c.id).map { [ branch_names.fetch(it.branch_id), it.name, it.kind ] }.sort
            requirements = Appointments::ServiceResourceRequirement.where(company_id: c.id).map { [ Appointments::Service.find(it.service_id).name, it.kind ] }.sort
            slots = Appointments::WeeklySchedule.where(company_id: c.id)
            branch_slots = slots.where(owner_type: "branch").group(:branch_id).count.map { |id, n| [ branch_names.fetch(id), n ] }.sort
            professional_slots = Appointments::Professional.where(company_id: c.id).order(:display_name).map do |p|
              mine = slots.where(professional_id: p.id)
              [ p.display_name, branch_names.fetch(mine.first.branch_id), mine.map(&:weekday).uniq.sort ]
            end
            resource_slots = Appointments::Resource.where(company_id: c.id).order(:name).filter_map do |r|
              count = slots.where(resource_id: r.id).count
              [ r.name, count ] if count.positive?
            end
            staff = { professionals:, resources:, requirements:, branch_slots:, professional_slots:, resource_slots:,
                      time_offs: Appointments::TimeOff.where(company_id: c.id).count }.deep_stringify_keys
            [ c.currency, c.business_type, Tenancy::Branch.where(company_id: c.id).count, services, overrides, customers, staff ]
          end
          [ organization.name, companies ]
        end
      end
      puts report.to_json
    RUBY
  end

  it "crea las organizaciones de demo y es idempotente (correrlo dos veces no duplica nada)", :aggregate_failures do
    app.run!("bin/rails", "db:seed")
    first = census
    app.run!("bin/rails", "db:seed")

    expect(census).to eq(first)
    expect(JSON.parse(first)).to eq(expected_census)
  end

  it "Sandra Gómez es la misma persona en dos empresas del grupo: un registro por empresa, con horarios independientes", :aggregate_failures do
    app.run!("bin/rails", "db:seed")
    app.run!("bin/rails", "db:seed")

    report = JSON.parse(app.rails_runner(<<~RUBY))
      sandra = Identity::User.find_by!(email: "profesional@salud-estilo.ceiba.test")
      org = Tenancy::Organization.find_by!(name: "Grupo Salud & Estilo")
      rows = Tenancy.with_context(organization: org) do
        Appointments::Professional.where(user_id: sandra.id).map do |p|
          weekdays = Appointments::WeeklySchedule.where(professional_id: p.id).pluck(:weekday).uniq.sort
          [ Tenancy::Directory.companies.find(p.company_id).slug, p.display_name, weekdays ]
        end.sort
      end
      puts rows.to_json
    RUBY

    expect(report).to eq([ [ "clinica-sonrisa", "Sandra Gómez", [ 2, 4 ] ], [ "salon-estilo", "Sandra Gómez", [ 1, 3, 5 ] ] ])
  end

  describe "usuarios de demo (M0.07)" do
    let(:users_report) do
      lambda do
        app.rails_runner('puts Identity::User.order(:email).pluck(:email, :full_name).to_json')
      end
    end

    it "crea un usuario por organización de demo y es idempotente", :aggregate_failures do
      app.run!("bin/rails", "db:seed")
      first = users_report.call
      app.run!("bin/rails", "db:seed")

      expect(users_report.call).to eq(first)
      expect(JSON.parse(first).map(&:first)).to include("luis@salud-estilo.ceiba.test", "rosa@barberia-guegu.ceiba.test", "ana@multi-org.ceiba.test")
    end

    it "ana (M0.12) tiene acceso a DOS organizaciones: dueña de Café Volcán y org_admin de Barbería El Güegüense (criterio 2 del E2E)" do
      app.run!("bin/rails", "db:seed")
      app.run!("bin/rails", "db:seed")

      names = app.rails_runner(<<~RUBY)
        user = Identity::User.find_by!(email: "ana@multi-org.ceiba.test")
        principal = Access::Principal::User.new(user)
        puts Tenancy::Directory.organizations_for(principal.organization_ids).map(&:name).sort.to_json
      RUBY

      expect(JSON.parse(names)).to eq([ "Barbería El Güegüense", "Café Volcán" ])
    end

    it "la contraseña de desarrollo documentada permite iniciar sesión" do
      app.run!("bin/rails", "db:seed")

      token = app.rails_runner('puts Identity::Authenticate.call(email: "rosa@barberia-guegu.ceiba.test", password: "ceiba-demo-2026").token.present?')

      expect(token).to eq("true")
    end

    it "SEED_DEMO_PASSWORD reemplaza la contraseña de desarrollo" do
      app.run!("bin/rails", "db:seed", env: { "SEED_DEMO_PASSWORD" => "otra-contraseña-segura" })

      ok = app.rails_runner('puts Identity::Authenticate.call(email: "luis@salud-estilo.ceiba.test", password: "otra-contraseña-segura").token.present?')

      expect(ok).to eq("true")
    end

    it "una SEED_DEMO_PASSWORD vacía cuenta como ausente: en producción no siembra usuarios" do
      app.write("config/database.yml", app.read("config/database.yml").gsub("ceiba_production", app.database))
      output = app.run!("bin/rails", "db:seed", env: { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x" * 64, "RAILS_LOG_LEVEL" => "fatal", "SEED_DEMO_PASSWORD" => "" })

      expect(output).to include("define SEED_DEMO_PASSWORD")
      expect(users_report.call).to eq("[]")
    end

    it "en producción NO siembra usuarios con la contraseña de desarrollo (exige SEED_DEMO_PASSWORD)", :aggregate_failures do
      app.write("config/database.yml", app.read("config/database.yml").gsub("ceiba_production", app.database))
      output = app.run!("bin/rails", "db:seed", env: { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x" * 64, "RAILS_LOG_LEVEL" => "fatal" })

      expect(output).to include("SEED_DEMO_PASSWORD")
      expect(users_report.call).to eq("[]")
    end
  end

  describe "roles de demo (M0.08)" do
    let(:memberships_report) do
      lambda do
        app.rails_runner(<<~RUBY)
          rows = Tenancy::Organization.order(:name).flat_map do |organization|
            Tenancy.with_context(organization:) do
              Access::Membership.includes(:role).map do |m|
                email = Identity::User.find(m.user_id).email
                scope = m.branch_id ? Tenancy::Branch.find(m.branch_id).name : (m.company_id ? Tenancy::Company.find(m.company_id).slug : "organización")
                [ email, m.role.key, scope ]
              end
            end
          end
          puts rows.sort.to_json
        RUBY
      end
    end

    it "siembra dueño, gerente de empresa, gerentes de sucursal, recepcionistas y profesionales, y es idempotente" do
      app.run!("bin/rails", "db:seed")
      first = memberships_report.call
      app.run!("bin/rails", "db:seed")

      expect(memberships_report.call).to eq(first)
      expect(JSON.parse(first)).to include(
        [ "rosa@barberia-guegu.ceiba.test", "org_owner", "organización" ],
        [ "luis@salud-estilo.ceiba.test", "org_owner", "organización" ],
        [ "marta@salud-estilo.ceiba.test", "company_manager", "salon-estilo" ],
        [ "gerente@barberia-guegu.ceiba.test", "branch_manager", "Sucursal Centro" ],
        [ "recepcion@barberia-guegu.ceiba.test", "receptionist", "Sucursal Centro" ],
        [ "profesional@salud-estilo.ceiba.test", "professional", "Estilo Centro" ]
      )
      expect(JSON.parse(first).map { |row| row[1] }.uniq).to match_array(%w[org_owner org_admin company_manager branch_manager receptionist professional])
    end

    it "los usuarios de demo entran por la API y ven solo lo que su rol permite", :aggregate_failures do
      app.run!("bin/rails", "db:seed")

      ok = app.rails_runner(<<~RUBY)
        org = Tenancy::Organization.find_by!(name: "Grupo Salud & Estilo")
        marta = Identity::User.find_by!(email: "marta@salud-estilo.ceiba.test")
        principal = Access::Principal::User.new(Identity::Principal::User.new(id: marta.id, email: marta.email, full_name: marta.full_name))
        Tenancy.with_context(organization: org) { principal.activate!(org.id) }
        puts principal.can?("platform.branch.create", Access::Scope.organization(org.id))
      RUBY

      expect(ok).to eq("false") # company_manager does not create things at organization level
    end
  end

  it "db:seed corre como app_user (el rol se comprueba DENTRO del seed real, no en un runner aparte)" do
    app.write("db/seeds.rb", "#{app.read('db/seeds.rb')}\nputs \"seed_role=\#{ActiveRecord::Base.connection.select_value('SELECT current_user')}\"\n")

    expect(app.run!("bin/rails", "db:seed")).to include("seed_role=app_user")
  end

  it "un conflicto de slug que NO es de la primera empresa del grupo no se disfraza de 'Ya existe' y no deja el grupo a medias" do
    app.rails_runner(<<~RUBY)
      Tenancy::ProvisionOrganization.call(organization: { name: "Intruso" }, company: { name: "Salón", slug: "salon-estilo", business_type: "salon", currency: "NIO" }, branch: { name: "X" })
    RUBY
    output, status = app.run("bin/rails", "db:seed")

    expect(status).not_to be_success
    expect(output).not_to include("Ya existe: Grupo Salud & Estilo")
    expect(app.rails_runner('puts Tenancy::Organization.where(name: "Grupo Salud & Estilo").count')).to eq("0")
  end

  it "crea todo solo a través de la API pública de tenancy (sin tocar los modelos privados)" do
    expect(Rails.root.join("db/seeds.rb").read).not_to match(/(Tenancy::(Organization|Company|Branch)|Identity::(User|Session))\b/)
  end
end
