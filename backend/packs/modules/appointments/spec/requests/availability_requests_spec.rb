require "rails_helper"

# The panel asks the engine with the staff window: what it lists is what the same panel can book (booking inside the lead time or
# beyond the advance limit is allowed there), so the grid never hides a slot that POST would accept.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Disponibilidad del panel: ventana de reserva" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
    let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  # Monday 16 Nov 2026; 10:00 local (America/Managua, UTC-6) is 16:00Z.
  let(:monday) { "2026-11-16" }

  before do
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  after { travel_back }

  # Signs in again after the clock moves: the session is checked against the (travelled) time.
  def starts
    headers = sign_in(receptionist).csrf_headers
    path = "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/availability"
    get(path, params: { service_ids: service.id, professional_id: professional.id, from: monday, to: monday }, headers:)
    response.parsed_body.fetch("data").pluck("starts_at")
  end

  it "lista un hueco que cae dentro de la anticipación mínima de la sucursal" do
    travel_to Time.utc(2026, 11, 16, 15, 30)

    expect(starts).to include("2026-11-16T16:00:00.000Z")
  end

  it "lista un hueco más allá de los días máximos de anticipación de la sucursal" do
    travel_to Time.utc(2026, 8, 1, 12)

    expect(starts).to include("2026-11-16T16:00:00.000Z")
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
