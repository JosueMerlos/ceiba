require "rails_helper"

# Real races, as in the booking concurrency spec: COMMIT, one thread and one connection per attempt, released at once by a barrier.
# Nothing is mocked: the row lock and the conditioned UPDATE decide who wins.
RSpec.describe Appointments::Reschedule do
  self.use_transactional_tests = false

  let!(:organization) { create(:organization) }
  let(:ten) { Time.utc(2026, 11, 16, 16) } # Monday, 10:00 local (America/Managua, UTC-6)
  let(:now) { Time.utc(2026, 11, 1) }

  after { purge_organizations([ organization ]) }

  def build_world
    with_tenant(organization) do
      company = create(:company)
      Modules::Enable.call(company:, key: "appointments")
      branch = create(:branch, company:)
      service = create(:service, company:, duration_minutes: 30)
      create(:weekly_schedule, branch:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      professional = create(:professional, company:)
      create(:professional_branch_assignment, professional:, branch:)
      create(:professional_service, professional:, service:)
      create(:weekly_schedule, branch:, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
      choice = Appointments::Availability::ProfessionalChoice.of(professional)
      original = Appointments::Book.call(company:, branch:, customer_id: create(:customer, company:).id, services: [ service ], professional: choice,
                                         starts_at: ten, source: "panel", now:)
      { company:, branch:, choice:, original: }
    end
  end

  def race(world, targets)
    barrier = Concurrent::CyclicBarrier.new(targets.size)
    threads = targets.map do |starts_at|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          raise "barrier timeout" unless barrier.wait(30)

          Tenancy.with_context(organization:) do
            described_class.call(appointment: world[:original], company: world[:company], branch: world[:branch], starts_at:,
                                 professional: world[:choice], source: "panel", now:)
          end
        rescue StandardError => error
          error
        end
      end
    end
    threads.map(&:value)
  end

  it "dos reprogramaciones simultáneas a horas distintas: una cita nueva y la otra InvalidTransition, nunca SlotUnavailable", :aggregate_failures do
    world = build_world

    results = race(world, [ ten + 1.hour, ten + 2.hours ])

    expect(results.grep(Appointments::Appointment).size).to eq(1)
    expect(results.grep_v(Appointments::Appointment).map(&:class)).to eq([ Appointments::InvalidTransition ])
    with_tenant(organization) do
      expect(Appointments::Appointment.where(rescheduled_from_id: world[:original].id).count).to eq(1)
      expect(world[:original].reload.status).to eq("rescheduled")
      expect(Events::OutboxEvent.where(name: "appointments.appointment_rescheduled.v1").count).to eq(1)
    end
  end

  it "diez reprogramaciones simultáneas de la misma cita: una sola sucesora", :aggregate_failures do
    world = build_world

    results = race(world, Array.new(10) { |index| ten + 15.minutes * (index + 1) })

    expect(results.grep(Appointments::Appointment).size).to eq(1)
    expect(results.grep_v(Appointments::Appointment).map(&:class).uniq).to eq([ Appointments::InvalidTransition ])
    expect(with_tenant(organization) { Appointments::Appointment.where(rescheduled_from_id: world[:original].id).count }).to eq(1)
  end
end
