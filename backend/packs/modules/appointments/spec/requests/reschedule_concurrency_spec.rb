require "rails_helper"

# Real race over HTTP: two sessions reschedule the same appointment to DIFFERENT times at once, with distinct keys. No transactional
# fixtures: real COMMITs and one connection per request, released together by a barrier. The row lock decides.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Reprogramación: carrera por HTTP" do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  let!(:world) { build_access_world }
  let(:user) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }

  before do
    travel_to Time.utc(2026, 11, 11, 12)
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  after do
    travel_back
    purge_organizations([ world.organization ], user_ids: [ user.id ])
    Identity::Session.where(user_id: user.id).delete_all
    Identity::User.where(id: user.id).delete_all
  end

  def original
    @original ||= with_tenant(world.organization) do
      Appointments::Book.call(company: world.company_a, branch: world.branch_a1, customer_id: customer.id, services: [ service ],
                              professional: Appointments::Availability::ProfessionalChoice.of(professional), starts_at: Time.utc(2026, 11, 16, 16), source: "panel")
    end
  end

  def path = "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/appointments/#{original.id}/reschedule"

  # The logins happen before the race: only the POSTs compete.
  def race(starts)
    sessions = starts.map { open_session.then { |browser| [ browser, sign_in(user, browser:).csrf_token ] } }
    barrier = Concurrent::CyclicBarrier.new(starts.size)
    sessions.zip(starts).map do |(browser, csrf_token), starts_at|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          raise "barrier timeout" unless barrier.wait(30)

          browser.post path, params: { starts_at: }, headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => SecureRandom.uuid }, as: :json
          browser.response
        end
      end
    end.map(&:value)
  end

  it "dos reprogramaciones simultáneas a horas distintas: un 201 y un 409 invalid_transition, y una sola cita nueva", :aggregate_failures do
    original

    responses = race([ "2026-11-16T11:00:00-06:00", "2026-11-16T12:00:00-06:00" ])

    expect(responses.map(&:status).tally).to eq(201 => 1, 409 => 1)
    expect(responses.find { it.status == 409 }.parsed_body["code"]).to eq("appointments.invalid_transition")
    with_tenant(world.organization) do
      expect(Appointments::Appointment.where(rescheduled_from_id: original.id).pluck(:id)).to eq([ responses.find { it.status == 201 }.parsed_body.dig("data", "id") ])
      expect(original.reload.status).to eq("rescheduled")
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
