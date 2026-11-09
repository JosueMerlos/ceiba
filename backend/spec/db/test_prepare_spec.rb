require "rails_helper"

# `db:prepare` sobre una base de test VACÍA (como en el job backend-test de CI) carga el esquema y, en Rails 8.1, también
# los seeds. Los specs asumen una base sin organizaciones: la base de test no se siembra nunca.
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
