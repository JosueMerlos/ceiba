require "rails_helper"

# Real race: two concurrent provisions with the SAME slug. Both pass the uniqueness validation (neither sees the other's row
# yet); the database UNIQUE constraint wins and the loser gets a domain error, not ActiveRecord::RecordNotUnique. No
# transactional fixtures: real COMMITs and separate connections are needed.
RSpec.describe Tenancy::ProvisionOrganization, ".call" do
  self.use_transactional_tests = false

  let(:slug) { "carrera-#{SecureRandom.hex(3)}" }
  let(:hooks) { [] }

  after do
    hooks.each { |hook| described_class.remove_after_provision(hook) }
    purge_organizations(Tenancy::Organization.where("name LIKE 'Carrera %'").to_a)
  end

  def provision(name) = described_class.call(organization: { name: "Carrera #{name}" }, company: { name: name, slug:, business_type: "salon", currency: "NIO" }, branch: { name: "Centro" })

  # DETERMINISTIC wait: B is truly blocked on A's transaction (an ungranted transactionid lock), not "for a while". Without
  # it the test could exercise another path (validation) instead of RecordNotUnique.
  def wait_until_blocked_on_unique_index
    Timeout.timeout(10) do
      sleep 0.05 until ApplicationRecord.connection.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'transactionid' AND NOT granted").to_i.positive?
    end
  end

  # Runs A until its company is inserted WITHOUT commit; then starts B (which cannot see it and blocks on the INSERT because
  # of the unique index); once A is released, B loses. Returns [A's result, B's thread].
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
