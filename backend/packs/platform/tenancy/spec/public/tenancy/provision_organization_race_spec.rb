require "rails_helper"

# Carrera real: dos provisiones concurrentes con el MISMO slug. Ambas pasan la validación de unicidad (ninguna ve aún
# la fila de la otra); gana la restricción UNIQUE de la base y el perdedor recibe un error de dominio, no un
# ActiveRecord::RecordNotUnique. Sin fixtures transaccionales: hacen falta COMMITs y conexiones distintas.
RSpec.describe Tenancy::ProvisionOrganization, "con provisiones concurrentes" do
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

  it "el perdedor de la carrera recibe slug_taken y solo queda una organización" do
    inserted = Queue.new
    release = Queue.new
    # El hook del PRIMERO corre cuando su empresa ya está insertada pero sin COMMIT: ahí arranca el segundo.
    hooks << described_class.after_provision(lambda do |result|
      if result.organization.name == "Carrera A"
        inserted << :ready
        release.pop(timeout: 10)
      end
    end)

    winner = Thread.new { provision("A") }
    inserted.pop(timeout: 10)
    loser = Thread.new { provision("B") }
    sleep 0.5 # B ya validó (no ve a A) y está bloqueado en el INSERT por el índice único
    release << :go

    expect(winner.value.company.slug).to eq(slug)
    expect { loser.value }.to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:slug_taken) }
    expect(Tenancy::Organization.where("name LIKE 'Carrera %'").pluck(:name)).to eq([ "Carrera A" ])
  end
end
