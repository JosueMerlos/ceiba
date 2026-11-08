require "rails_helper"

# Carrera real: dos provisiones concurrentes con el MISMO slug. Ambas pasan la validación de unicidad (ninguna ve aún
# la fila de la otra); gana la restricción UNIQUE de la base y el perdedor recibe un error de dominio, no un
# ActiveRecord::RecordNotUnique. Sin fixtures transaccionales: hacen falta COMMITs y conexiones distintas.
RSpec.describe Tenancy::ProvisionOrganization, ".call" do
  self.use_transactional_tests = false

  let(:slug) { "carrera-#{SecureRandom.hex(3)}" }
  let(:hooks) { [] }

  after do
    hooks.each { |hook| described_class.remove_after_provision(hook) }
    organizations = Tenancy::Organization.where("name LIKE 'Carrera %'")
    organizations.each do |organization|
      Tenancy.with_context(organization:) do
        Tenancy::Branch.delete_all
        Tenancy::Company.delete_all
      end
    end
    organizations.delete_all
  end

  def provision(name) = described_class.call(organization: { name: "Carrera #{name}" }, company: { name: name, slug:, business_type: "salon", currency: "NIO" }, branch: { name: "Centro" })

  # Espera DETERMINISTA: B está de verdad bloqueada esperando a la transacción de A (un lock de tipo transactionid sin
  # conceder), no "un rato". Sin esto el test podría ejercitar otra ruta (validación) y no RecordNotUnique.
  def wait_until_blocked_on_unique_index
    Timeout.timeout(10) do
      sleep 0.05 until ApplicationRecord.connection.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'transactionid' AND NOT granted").to_i.positive?
    end
  end

  # Corre A hasta tener su empresa insertada SIN commit; entonces arranca B (que no la ve y se bloquea en el INSERT por
  # el índice único); al soltar A, B pierde. Devuelve [resultado de A, hilo de B].
  def race
    inserted = Queue.new
    release = Queue.new
    hooks << described_class.after_provision(lambda do |result|
      next unless result.organization.name == "Carrera A"

      inserted << :ready
      release.pop(timeout: 10)
    end)
    winner = Thread.new { provision("A") }
    inserted.pop(timeout: 10)
    loser = Thread.new do
      Thread.current.report_on_exception = false
      provision("B")
    end
    wait_until_blocked_on_unique_index
    release << :go
    [ winner.value, loser ]
  end

  it "el perdedor de la carrera recibe slug_taken (error de dominio, no RecordNotUnique)" do
    winner, loser = race

    expect(winner.company.slug).to eq(slug)
    expect { loser.value }.to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:slug_taken) }
  end

  it "solo queda la organización ganadora" do
    _winner, loser = race
    expect { loser.value }.to raise_error(Tenancy::ProvisioningFailed)

    expect(Tenancy::Organization.where("name LIKE 'Carrera %'").pluck(:name)).to eq([ "Carrera A" ])
  end
end
