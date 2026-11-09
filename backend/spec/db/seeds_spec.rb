require "rails_helper"

# Criterio 10 de M0.05: con una BD vacía, `bin/rails db:seed` dos veces deja exactamente las 2 organizaciones de demo.
# Corre sobre una copia de la app con su propia base (como app_user, el rol de los seeds) y en procesos nuevos.
RSpec.describe "db/seeds.rb" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_seeds_probe").create }

  before { app.db!("db:create", "db:migrate") }

  after { app.destroy }

  def census
    app.rails_runner(<<~RUBY)
      report = Tenancy::Organization.order(:name).map do |organization|
        Tenancy.with_context(organization:) do
          [ organization.name, Tenancy::Company.order(:slug).map { |c| [ c.currency, c.business_type, Tenancy::Branch.where(company_id: c.id).count ] } ]
        end
      end
      puts report.to_json
    RUBY
  end

  it "crea las dos organizaciones de demo y es idempotente (correrlo dos veces no duplica nada)" do
    app.run!("bin/rails", "db:seed")
    first = census
    app.run!("bin/rails", "db:seed")

    expect(census).to eq(first)
    expect(JSON.parse(first)).to eq(
      [
        [ "Barbería El Güegüense", [ [ "NIO", "barbershop", 1 ] ] ],
        [ "Grupo Salud & Estilo", [ [ "USD", "dental", 1 ], [ "NIO", "salon", 2 ] ] ]
      ]
    )
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
      expect(JSON.parse(first).map(&:first)).to include("luis@salud-estilo.ceiba.test", "rosa@barberia-guegu.ceiba.test")
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

      expect(ok).to eq("false") # company_manager no crea cosas a nivel de organización
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
