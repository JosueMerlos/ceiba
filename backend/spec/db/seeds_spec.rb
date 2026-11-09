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
      expect(JSON.parse(first)).to eq(
        [
          [ "luis@salud-estilo.ceiba.test", "Luis Ortega" ],
          [ "rosa@barberia-guegu.ceiba.test", "Rosa Mendoza" ]
        ]
      )
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

    it "en producción NO siembra usuarios con la contraseña de desarrollo (exige SEED_DEMO_PASSWORD)", :aggregate_failures do
      app.write("config/database.yml", app.read("config/database.yml").gsub("ceiba_production", app.database))
      output = app.run!("bin/rails", "db:seed", env: { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x" * 64, "RAILS_LOG_LEVEL" => "fatal" })

      expect(output).to include("SEED_DEMO_PASSWORD")
      expect(users_report.call).to eq("[]")
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
