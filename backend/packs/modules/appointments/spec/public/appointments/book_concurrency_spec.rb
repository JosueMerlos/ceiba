require "rails_helper"

# Real races: COMMIT, one thread and one connection per attempt, all released at once by a barrier. What is under test is that the
# database (exclusions) and the advisory locks decide, so the races mock nothing.
RSpec.describe Appointments::Book do
  self.use_transactional_tests = false

  let!(:organization) { create(:organization) }
  let(:starts_at) { Time.utc(2026, 11, 16, 16) } # Monday, 10:00 local (America/Managua, UTC-6)
  let(:user_ids) { [] }

  after do
    purge_organizations([ organization ], user_ids:)
    Identity::User.where(id: user_ids).delete_all
  end

  # Everything committed for real: a company with a branch, a service, a customer and the weekly hours.
  def build_company
    with_tenant(organization) do
      company = create(:company)
      Modules::Enable.call(company:, key: "appointments")
      branch = create(:branch, company:)
      service = create(:service, company:, duration_minutes: 30)
      create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      { company:, branch:, service:, customer: create(:customer, company:) }
    end
  end

  def add_professional(world, user_id: nil)
    with_tenant(organization) do
      create(:professional, company: world[:company], user_id:).tap do |professional|
        create(:professional_branch_assignment, professional:, branch: world[:branch])
        create(:professional_service, professional:, service: world[:service])
        create(:weekly_schedule, branch: world[:branch], professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      end
    end
  end

  def add_chairs(world, count)
    with_tenant(organization) do
      create(:service_resource_requirement, service: world[:service], kind: "chair")
      Array.new(count) { create(:resource, branch: world[:branch], kind: "chair") }
    end
  end

  # One attempt per [world, professional]; returns the appointment or the error each one raised, in order.
  def race(attempts)
    barrier = Concurrent::CyclicBarrier.new(attempts.size)
    threads = attempts.map do |world, professional|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          barrier.wait(30)
          Tenancy.with_context(organization:) { book(world, professional) }
        rescue StandardError => error
          error
        end
      end
    end
    threads.map(&:value)
  end

  def book(world, professional)
    described_class.call(company: world[:company], branch: world[:branch], customer_id: world[:customer].id, services: [ world[:service] ],
                         professional: Appointments::Availability::ProfessionalChoice.of(professional), starts_at:, source: "panel", now: Time.utc(2026, 11, 1))
  end

  def appointments = with_tenant(organization) { Appointments::Appointment.order(:id).to_a }
  def winners(results) = results.grep(Appointments::Appointment)
  def failures(results) = results.reject { it.is_a?(Appointments::Appointment) }

  it "10 hilos sobre el mismo hueco y profesional: una cita y nueve SlotUnavailable", :aggregate_failures do
    world = build_company
    professional = add_professional(world)

    results = race(Array.new(10) { [ world, professional ] })

    expect(winners(results).size).to eq(1)
    expect(failures(results).map(&:class)).to eq([ Appointments::SlotUnavailable ] * 9)
    expect(appointments.size).to eq(1)
    expect(with_tenant(organization) { Events::OutboxEvent.where(name: "appointments.appointment_booked.v1").count }).to eq(1)
  end

  it "10 hilos con la misma persona en 10 empresas: una cita y nueve PersonUnavailable", :aggregate_failures do
    person = create(:user)
    user_ids << person.id
    attempts = Array.new(10) do
      world = build_company
      user_with_role("receptionist", organization, branch: world[:branch], user: person)
      [ world, add_professional(world, user_id: person.id) ]
    end

    results = race(attempts)

    expect(winners(results).size).to eq(1)
    expect(failures(results).map(&:class)).to eq([ Appointments::PersonUnavailable ] * 9)
    expect(appointments.size).to eq(1)
  end

  it "un solo sillón y profesionales distintos a la vez: una cita, el resto SlotUnavailable y ningún Deadlocked", :aggregate_failures do
    world = build_company
    chair = add_chairs(world, 1).first
    attempts = Array.new(6) { [ world, add_professional(world) ] }

    results = race(attempts)

    expect(failures(results).map(&:class).uniq).to eq([ Appointments::SlotUnavailable ])
    expect(winners(results).size).to eq(1)
    expect(appointments.map(&:resource_id)).to eq([ chair.id ])
  end

  it "dos sillones y tres hilos: dos citas en sillones distintos y un SlotUnavailable", :aggregate_failures do
    world = build_company
    chairs = add_chairs(world, 2)
    attempts = Array.new(3) { [ world, add_professional(world) ] }

    results = race(attempts)

    expect(winners(results).size).to eq(2)
    expect(failures(results).map(&:class)).to eq([ Appointments::SlotUnavailable ])
    expect(appointments.map(&:resource_id)).to match_array(chairs.map(&:id))
  end

  # The exclusion path: the engine is made to offer the taken slot, so the INSERT itself fails inside Book's savepoint.
  it "una ExclusionViolation dentro de una transacción externa la deja usable: se rescata, se sigue y se confirma otra escritura", :aggregate_failures do
    world = build_company
    professional = add_professional(world)
    with_tenant(organization) { create(:appointment, professional:, branch: world[:branch], customer: world[:customer], starts_at:) }
    allow(Appointments::Availability).to receive(:call).and_wrap_original do |original, **arguments|
      original.call(**arguments).then do |result|
        slot = Appointments::Availability::Slot.new(starts_at:, ends_at: starts_at + 30.minutes, professional_id: professional.id, resource_id: nil)
        result.with(slots: [ slot ])
      end
    end

    with_tenant(organization) do
      expect { book(world, professional) }.to raise_error(Appointments::SlotUnavailable)
      create(:service, company: world[:company], name: "Servicio posterior")
    end

    expect(with_tenant(organization) { Appointments::Service.where(name: "Servicio posterior").count }).to eq(1)
    expect(appointments.size).to eq(1)
  end
end
