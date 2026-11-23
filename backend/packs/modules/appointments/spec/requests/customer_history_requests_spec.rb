require "rails_helper"

# GET .../branches/:branch_id/customers/:customer_id/appointments: one customer's appointments at the route's branch, newest
# first, for the customer profile. Keyset pagination over (starts_at, id).
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Historial de citas de un cliente: peticiones" do
  let(:world) { build_access_world }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let(:signed_in) { sign_in(receptionist) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, name: "Corte") }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a, display_name: "Marta") }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }

  before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

  def path(customer_id: customer.id, branch: world.branch_a1)
    "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/branches/#{branch.id}/customers/#{customer_id}/appointments"
  end

  def history(query = {}, session: signed_in, **)
    get path(**), params: query, headers: session.csrf_headers
  end

  def appointment_at(starts_at, branch: world.branch_a1, status: "completed", who: customer, person: professional)
    with_tenant(world.organization) do
      columns = status == "cancelled" ? { cancelled_by: "staff", cancellation_reason: "other" } : {}
      create(:appointment, professional: person, branch:, customer: who, starts_at:, status:, **columns).tap { create(:appointment_service, appointment: it, service:) }
    end
  end

  def ids = response.parsed_body["data"].pluck("id")

  it "solo lista las citas de la sucursal de la ruta y de ese cliente" do
    own = appointment_at(Time.utc(2026, 11, 2, 15))
    appointment_at(Time.utc(2026, 11, 3, 15), branch: create_in(world.organization, :branch, company: world.company_a))
    appointment_at(Time.utc(2026, 11, 4, 15), who: create_in(world.organization, :customer, company: world.company_a))

    history

    expect(ids).to eq([ own.id ])
  end

  it "muestra el historial de un cliente archivado" do
    visit = appointment_at(Time.utc(2026, 11, 2, 15))
    with_tenant(world.organization) { Customers::Archive.call(customer:) }

    history

    expect(ids).to eq([ visit.id ])
  end

  it "un profesional, que solo ve sus propias citas, no lee el historial del cliente" do
    history(session: sign_in(user_with_role("professional", world, branch: world.branch_a1)))

    expect(response).to have_http_status(:forbidden)
  end

  it "responde 404 si el módulo de citas no está activo" do
    with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") }

    history

    expect(response).to have_http_status(:not_found)
  end

  it "hace el mismo número de consultas con 1 cita que con 6" do
    appointment_at(Time.utc(2026, 11, 2, 15))
    history
    count_one = count_queries { history }
    5.times { appointment_at(Time.utc(2026, 11, 3 + it, 15)) }

    expect(count_queries { history }).to eq(count_one)
  end

  it "con citas a la misma hora pagina sin perder ni repetir ninguna" do
    same = Array.new(3) { appointment_at(Time.utc(2026, 11, 2, 15), person: create_in(world.organization, :professional, company: world.company_a)) }
    older = appointment_at(Time.utc(2026, 11, 1, 15))

    pages = []
    history({ limit: 2 })
    pages << ids
    history({ limit: 2, after: response.parsed_body.dig("page", "next_cursor") })
    pages << ids

    expect(pages).to eq([ same.map(&:id).sort.reverse.first(2), [ same.map(&:id).min, older.id ] ])
  end

  it "un cursor alterado responde 400" do
    history({ after: "no-es-un-cursor" })

    expect([ response.status, response.parsed_body["code"] ]).to eq([ 400, "pagination.invalid_cursor" ])
  end

  def count_queries(&)
    queries = 0
    counter = ->(*, payload) { queries += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE|SET|RESET)/i) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    queries
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
