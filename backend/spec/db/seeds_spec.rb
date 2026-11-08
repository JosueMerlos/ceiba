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

  it "los seeds corren como app_user" do
    output = app.run!("bin/rails", "runner", "puts ActiveRecord::Base.connection.select_value('SELECT current_user')")

    expect(output.strip).to eq("app_user")
  end

  it "crea todo solo a través de la API pública de tenancy (sin tocar los modelos privados)" do
    expect(Rails.root.join("db/seeds.rb").read).not_to match(/Tenancy::(Organization|Company|Branch)\b/)
  end
end
