require "rails_helper"

# Real races: COMMIT, one thread and one connection per attempt, all released at once by a barrier. What is under test is that the
# database (exclusions) and the advisory locks decide, so nothing is mocked: the exclusion path commits a competing row from a
# second connection at the exact statement where Book is about to insert.
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
          raise "barrier timeout" unless barrier.wait(30)

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

  # What Book rescued to raise its conflict: nothing when the locks and the revalidation decided, an exclusion or a deadlock when
  # the database had to.
  def causes(results) = failures(results).filter_map(&:cause).map(&:class)

  it "10 hilos sobre el mismo hueco y profesional: una cita y nueve SlotUnavailable", :aggregate_failures do
    world = build_company
    professional = add_professional(world)

    results = race(Array.new(10) { [ world, professional ] })

    expect(winners(results).size).to eq(1)
    expect(failures(results).map(&:class)).to eq([ Appointments::SlotUnavailable ] * 9)
    expect(causes(results)).to be_empty
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
    expect(causes(results)).to be_empty
    expect(appointments.size).to eq(1)
  end

  it "un solo sillón y profesionales distintos a la vez: una cita, el resto SlotUnavailable por el candado y ni un Deadlocked ni una exclusión de por medio", :aggregate_failures do
    world = build_company
    chair = add_chairs(world, 1).first
    attempts = Array.new(6) { [ world, add_professional(world) ] }

    results = race(attempts)

    expect(failures(results).map(&:class).uniq).to eq([ Appointments::SlotUnavailable ])
    expect(causes(results)).to be_empty
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
    expect(causes(results)).to be_empty
    expect(appointments.map(&:resource_id)).to match_array(chairs.map(&:id))
  end

  # Runs `on_insert` once, just before Book's INSERT of the appointment, on another connection and to completion, so a competing
  # row is committed after the revalidation has passed and before the exclusion constraint is consulted. Needs a subscriber that
  # responds to start/finish: a block subscriber only runs after the statement.
  def compete_before_insert(on_insert)
    fired = false
    subscriber = Object.new
    subscriber.define_singleton_method(:start) do |_name, _id, payload|
      next if fired || !payload[:sql].start_with?('INSERT INTO "appointments"')

      fired = true
      Thread.new { ApplicationRecord.connection_pool.with_connection { on_insert.call } }.join
    end
    subscriber.define_singleton_method(:finish) { |*| }
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record", subscriber)
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  # What reached Rails.error while the block ran, through a real subscriber (the reporter is not mocked).
  def reported_errors
    reports = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, handled:, severity:, context:, source: nil| reports << { error:, handled:, severity:, context:, source: } }
    Rails.error.subscribe(subscriber)
    yield
    reports
  ensure
    Rails.error.unsubscribe(subscriber)
  end

  def book_after_competitor_commits(world, professional)
    competitor = -> { Tenancy.with_context(organization:) { create(:appointment, professional:, branch: world[:branch], customer: world[:customer], starts_at:) } }
    compete_before_insert(competitor) do
      expect { book(world, professional) }.to raise_error(Appointments::SlotUnavailable) { |error| expect(error.cause).to be_a(ActiveRecord::ExclusionViolation) }
    end
  end

  it "una cita que se confirma tras la revalidación y antes del INSERT: ExclusionViolation traducida a SlotUnavailable y la transacción externa sigue usable", :aggregate_failures do
    world = build_company
    professional = add_professional(world)

    with_tenant(organization) do
      book_after_competitor_commits(world, professional)
      create(:service, company: world[:company], name: "Servicio posterior")
    end

    expect(with_tenant(organization) { Appointments::Service.where(name: "Servicio posterior").count }).to eq(1)
    expect(appointments.size).to eq(1)
    expect(with_tenant(organization) { Appointments::AppointmentService.count + Events::OutboxEvent.where(name: "appointments.appointment_booked.v1").count }).to eq(0)
    expect(with_tenant(organization) { Audit::Event.where(action: "appointments.appointment.booked").count }).to eq(0)
  end

  it "esa ExclusionViolation traducida se reporta a Rails.error con solo ids, sin PII", :aggregate_failures do
    world = build_company
    professional = add_professional(world)

    reports = reported_errors { with_tenant(organization) { book_after_competitor_commits(world, professional) } }

    expect(reports.size).to eq(1)
    expect(reports.first).to include(error: an_instance_of(ActiveRecord::ExclusionViolation), handled: true)
    expect(reports.first[:context]).to eq(company_id: world[:company].id, branch_id: world[:branch].id, professional_id: professional.id, starts_at: starts_at.iso8601)
  end

  it "el sillón ocupado por otro profesional tras la revalidación: la exclusión del recurso es la última barrera", :aggregate_failures do
    world = build_company
    chair = add_chairs(world, 1).first
    professional = add_professional(world)
    other = add_professional(world)
    competitor = lambda do
      Tenancy.with_context(organization:) { create(:appointment, professional: other, branch: world[:branch], customer: world[:customer], resource: chair, starts_at:) }
    end

    with_tenant(organization) do
      compete_before_insert(competitor) do
        expect { book(world, professional) }.to raise_error(Appointments::SlotUnavailable) { |error| expect(error.cause).to be_a(ActiveRecord::ExclusionViolation) }
      end
    end

    expect(appointments.map(&:professional_id)).to eq([ other.id ])
  end

  # Deletes a row from another committed connection, the way a competing writer would between Book's revalidation and its INSERT.
  def delete_row(model, id) = -> { Tenancy.with_context(organization:) { model.where(id:).delete_all } }

  it "el recurso que desaparece tras la revalidación: la FK compuesta del recurso es SlotUnavailable y se reporta", :aggregate_failures do
    world = build_company
    chair = add_chairs(world, 1).first
    professional = add_professional(world)

    reports = reported_errors do
      with_tenant(organization) do
        compete_before_insert(delete_row(Appointments::Resource, chair.id)) do
          expect { book(world, professional) }.to raise_error(Appointments::SlotUnavailable) { |error| expect(error.cause).to be_a(ActiveRecord::InvalidForeignKey) }
        end
      end
    end

    expect(reports.map { it[:error] }).to match([ an_instance_of(ActiveRecord::InvalidForeignKey) ])
    expect(reports.first).to include(handled: true, context: a_hash_including(branch_id: world[:branch].id, professional_id: professional.id))
    expect(appointments).to be_empty
  end

  it "cualquier otra FK rota (el cliente desaparece tras la validación) no se traduce: la InvalidForeignKey sale tal cual y no se reporta", :aggregate_failures do
    world = build_company
    professional = add_professional(world)

    reports = reported_errors do
      with_tenant(organization) do
        compete_before_insert(delete_row(Customers::Customer, world[:customer].id)) do
          expect { book(world, professional) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_appointments_customer/)
        end
      end
    end

    expect(reports).to be_empty
  end
end
