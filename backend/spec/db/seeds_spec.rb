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
    expect(Rails.root.join("db/seeds.rb").read).not_to match(/Tenancy::(Organization|Company|Branch)\b/)
  end
end
