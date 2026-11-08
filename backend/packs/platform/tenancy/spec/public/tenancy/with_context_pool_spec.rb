require "rails_helper"

# Sin fixtures transaccionales: aquí el COMMIT es real y hay varias conexiones del pool en juego. Demuestra que el
# `SET LOCAL app.organization_id` ni sobrevive al bloque ni es visible desde otra conexión (docs/architecture/03).
RSpec.describe "Tenancy.with_context y el pool de conexiones" do
  self.use_transactional_tests = false

  let!(:organization) { Tenancy::Organization.create!(name: "Pool") }

  after { Tenancy::Organization.where(id: organization.id).delete_all }

  def setting_on(connection) = connection.select_value("SELECT current_setting('app.organization_id', true)")

  def setting_from_another_connection
    Thread.new { ApplicationRecord.with_connection { |connection| setting_on(connection) } }.value
  end

  it "la transacción del contexto es real y termina al salir del bloque" do
    Tenancy.with_context(organization:) { expect(ApplicationRecord.connection.open_transactions).to eq(1) }

    expect(ApplicationRecord.connection.open_transactions).to eq(0)
  end

  it "el setting no sobrevive al bloque en la misma conexión" do
    Tenancy.with_context(organization:) { nil }

    expect(setting_on(ApplicationRecord.connection)).to be_blank
  end

  it "otra conexión del pool no ve el setting mientras el bloque corre ni después" do
    during = nil

    Tenancy.with_context(organization:) { during = setting_from_another_connection }

    expect(during).to be_blank
    expect(setting_from_another_connection).to be_blank
  end

  it "una conexión devuelta al pool y reutilizada llega sin contexto" do
    Thread.new { Tenancy.with_context(organization:) { nil } }.join

    expect(setting_from_another_connection).to be_blank
  end

  it "el setting tampoco sobrevive si el bloque lanza" do
    expect { Tenancy.with_context(organization:) { raise "boom" } }.to raise_error("boom")

    expect(setting_on(ApplicationRecord.connection)).to be_blank
    expect(setting_from_another_connection).to be_blank
  end

  it "dos hilos con organizaciones distintas ven cada uno solo la suya" do
    other = Tenancy::Organization.create!(name: "Otra pool")
    seen = Queue.new
    gate = Queue.new
    # El primero espera a que el segundo termine dentro de su bloque: la ejecución se solapa.
    run = lambda do |org|
      Tenancy.with_context(organization: org) do
        gate.pop(timeout: 5) if org == organization
        seen << [ org.id, setting_on(ApplicationRecord.connection), ActsAsTenant.current_tenant.id ]
        gate << :go if org == other
      end
    end
    [ organization, other ].map { |org| Thread.new { run.call(org) } }.each(&:join)

    expect(seen.size.times.map { seen.pop }).to all(satisfy { |id, setting, tenant| id == setting && id == tenant })
  ensure
    Tenancy::Organization.where(id: other&.id).delete_all
  end
end
