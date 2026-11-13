require "rails_helper"

# Real race over HTTP: ten receptionists-in-one (ten sessions, ten DISTINCT Idempotency-Keys) ask for the same slot at once. No
# transactional fixtures: real COMMITs, one connection per request and a barrier that releases all of them together. Nothing is
# mocked: the advisory locks, the engine's revalidation and the exclusion constraints decide.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Reserva de citas: carrera por HTTP" do
  self.use_transactional_tests = false

  let!(:world) { build_access_world }
  let(:user) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }
  let(:path) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/appointments" }
  # The first Monday at least two weeks ahead of the real clock, 10:00 in America/Managua (UTC-6): always in the future.
  let(:starts_at) { "#{(Date.current + 14).next_occurring(:monday).iso8601}T10:00:00-06:00" }
  let(:body) { { customer_id: customer.id, service_ids: [ service.id ], professional_id: professional.id, starts_at: } }

  before do
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  after do
    purge_organizations([ world.organization ], user_ids: [ user.id ])
    Identity::Session.where(user_id: user.id).delete_all
    Identity::User.where(id: user.id).delete_all
  end

  def appointments = with_tenant(world.organization) { Appointments::Appointment.order(:id).to_a }

  # The logins happen before the race: only the POSTs compete.
  def race(attempts)
    sessions = Array.new(attempts) { open_session.then { |browser| [ browser, sign_in(user, browser:).csrf_token ] } }
    barrier = Concurrent::CyclicBarrier.new(attempts)
    sessions.map do |browser, csrf_token|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          raise "barrier timeout" unless barrier.wait(30)

          browser.post path, params: body, headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => SecureRandom.uuid }, as: :json
          browser.response
        end
      end
    end.map(&:value)
  end

  it "10 peticiones con claves distintas al mismo hueco y profesional: un 201 y nueve 409 slot_unavailable", :aggregate_failures do
    responses = race(10)

    expect(responses.map(&:status).tally).to eq(201 => 1, 409 => 9)
    expect(responses.reject { it.status == 201 }.map { it.parsed_body["code"] }.uniq).to eq([ "appointments.slot_unavailable" ])
    expect(responses.find { it.status == 201 }.parsed_body.dig("data", "id")).to eq(appointments.sole.id)
    expect(with_tenant(world.organization) { Appointments::AppointmentService.count }).to eq(1)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
