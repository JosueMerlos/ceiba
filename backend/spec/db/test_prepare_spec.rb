require "rails_helper"

# `db:prepare` on an EMPTY test database (as in the CI backend-test job) loads the schema and, in Rails 8.1, the seeds
# too. The specs assume a database with no organizations: the test database is never seeded.
RSpec.describe "db:prepare en la base de test" do
  let(:app) { TemporaryAppCopy.new(database: "ceiba_prepare_probe").create }

  after { app.destroy }

  it "sobre una base vacía crea el esquema y NO siembra datos" do
    app.db!("db:drop", "db:prepare")

    expect(app.rails_runner("puts Tenancy::Organization.count")).to eq("0")
  end

  it "la configuración de test desactiva los seeds" do
    expect(ActiveRecord::Base.connection_db_config.seeds?).to be(false)
  end
end
