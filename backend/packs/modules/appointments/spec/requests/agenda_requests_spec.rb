require "rails_helper"

# GET .../branches/:branch_id/appointments: the branch's appointments between two LOCAL dates, for the agenda. Unpaginated up to a
# hard limit, with a fixed number of queries whatever the number of appointments.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Agenda de la sucursal: peticiones" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let!(:signed_in) { sign_in(receptionist) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }

  before do
    travel_to Time.utc(2026, 11, 11, 12)
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
  end

  after { travel_back }

  def path(branch: world.branch_a1) = "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/appointments/branches/#{branch.id}/appointments"

  def agenda(query = { from: "2026-11-16", to: "2026-11-22" }, session: signed_in, branch: world.branch_a1)
    get path(branch:), params: query, headers: session.csrf_headers
  end

  # An appointment with one snapshot line, at a UTC instant.
  def appointment_at(starts_at, person: professional, branch: world.branch_a1, status: "scheduled")
    with_tenant(world.organization) do
      columns = status == "cancelled" ? { cancelled_by: "staff", cancellation_reason: "other" } : {}
      create(:appointment, professional: person, branch:, starts_at:, status:, **columns).tap do |appointment|
        create(:appointment_service, appointment:, service:)
      end
    end
  end

  def ids = response.parsed_body["data"].map { it["id"] }
  def problem = response.parsed_body

  it "devuelve las citas de la sucursal entre las dos fechas locales, ordenadas por inicio, con sus líneas", :aggregate_failures do
    # America/Managua (UTC-6): local midnight of the 16th is 06:00Z; the 23rd starts at 06:00Z of the 23rd.
    later = appointment_at(Time.utc(2026, 11, 18, 16))
    first = appointment_at(Time.utc(2026, 11, 16, 6))
    last = appointment_at(Time.utc(2026, 11, 23, 5, 30))
    appointment_at(Time.utc(2026, 11, 16, 5, 30))
    appointment_at(Time.utc(2026, 11, 23, 6))
    appointment_at(Time.utc(2026, 11, 17, 16), branch: world.branch_a2)

    agenda

    expect(response).to have_http_status(:ok)
    expect(ids).to eq([ first.id, later.id, last.id ])
    expect(response.parsed_body["data"].first).to include("total_price_minor" => 20_000, "currency" => "NIO", "customer_id" => first.customer_id)
    expect(response.parsed_body["data"].first).not_to have_key("notes")
  end

  it "incluye las canceladas y reprogramadas (la agenda decide cómo mostrarlas)" do
    cancelled = appointment_at(Time.utc(2026, 11, 16, 16), status: "cancelled")

    agenda

    expect(response.parsed_body["data"].sole).to include("id" => cancelled.id, "status" => "cancelled", "cancelled_by" => "staff")
  end

  it "filtra por profesional" do
    other = create_in(world.organization, :professional, company: world.company_a)
    mine = appointment_at(Time.utc(2026, 11, 16, 16))
    appointment_at(Time.utc(2026, 11, 16, 16), person: other)

    agenda({ from: "2026-11-16", to: "2026-11-16", professional_id: professional.id })

    expect(ids).to eq([ mine.id ])
  end

  it "un profesional solo ve sus propias citas, pida el filtro que pida", :aggregate_failures do
    user = user_with_role("professional", world, branch: world.branch_a1)
    own = create_in(world.organization, :professional, company: world.company_a, user_id: user.id)
    create_in(world.organization, :professional_branch_assignment, professional: own, branch: world.branch_a1)
    mine = appointment_at(Time.utc(2026, 11, 16, 16), person: own)
    appointment_at(Time.utc(2026, 11, 16, 16))
    session = sign_in(user)

    agenda(session:)
    expect(ids).to eq([ mine.id ])
    agenda({ from: "2026-11-16", to: "2026-11-22", professional_id: professional.id }, session:)
    expect(ids).to eq([])
  end

  it "sin permiso de lectura de citas (org_owner solo ve conteos) es 403" do
    agenda(session: sign_in(user_with_role("org_owner", world)))

    expect([ response.status, problem["code"] ]).to eq([ 403, "access.forbidden" ])
  end

  it "admite 31 días y rechaza 32 o un rango invertido con 422 appointments.agenda_invalid", :aggregate_failures do
    agenda({ from: "2026-11-01", to: "2026-12-01" })
    expect(response).to have_http_status(:ok)

    agenda({ from: "2026-11-01", to: "2026-12-02" })
    expect([ response.status, problem["code"], problem.dig("errors", 0, "field"), problem.dig("errors", 0, "code") ])
      .to eq([ 422, "appointments.agenda_invalid", "to", "too_far" ])
    agenda({ from: "2026-11-10", to: "2026-11-09" })
    expect(problem.dig("errors", 0, "code")).to eq("before_from")
  end

  it "una fecha ausente es 400 request.invalid y una mal escrita o un profesional que no es UUID, 400 request.bad_request", :aggregate_failures do
    agenda({ to: "2026-11-16" })
    expect([ response.status, problem["code"] ]).to eq([ 400, "request.invalid" ])
    agenda({ from: "2026-02-30", to: "2026-03-01" })
    expect([ response.status, problem["code"] ]).to eq([ 400, "request.bad_request" ])
    agenda({ from: "2026-11-16", to: "2026-11-16", professional_id: "x" })
    expect([ response.status, problem["code"] ]).to eq([ 400, "request.bad_request" ])
  end

  it "con más citas que el límite duro responde 422 en vez de truncar en silencio", :aggregate_failures do
    stub_const("Appointments::Agenda::LIMIT", 2)
    3.times { |index| appointment_at(Time.utc(2026, 11, 16, 15) + index.hours) }

    agenda

    expect([ response.status, problem["code"], problem.dig("errors", 0, "code") ]).to eq([ 422, "appointments.agenda_invalid", "too_many_appointments" ])
  end

  it "en una zona con horario de verano, el día empieza en la medianoche local real" do
    # America/Santiago skips 00:00 -> 01:00 on Sunday 6 Sep 2026: that day starts at 01:00 local (04:00Z).
    with_tenant(world.organization) { world.branch_a1.update!(time_zone: "America/Santiago") }
    on_the_day = appointment_at(Time.utc(2026, 9, 6, 4))
    appointment_at(Time.utc(2026, 9, 6, 3, 30))

    agenda({ from: "2026-09-06", to: "2026-09-06" })

    expect(ids).to eq([ on_the_day.id ])
  end

  describe "rendimiento (una semana con 200 citas)" do
    def queries_for_agenda
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("SAVEPOINT", "RELEASE", "ROLLBACK") }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { agenda }
      count
    end

    # Five professionals, 08:00-16:00 local, every 30 minutes, Monday to Friday: 5 x 8 x 5 = 200.
    def fill_week(limit)
      people = Array.new(5) { create_in(world.organization, :professional, company: world.company_a) }
      slots = (16..20).flat_map { |day| (0...16).map { |half| Time.utc(2026, 11, day, 14) + (half * 30).minutes } }
      people.product(slots).first(limit).each { |person, starts_at| appointment_at(starts_at, person:) }
    end

    it "el número de consultas no crece con el número de citas", :aggregate_failures do
      fill_week(20)
      few = queries_for_agenda
      expect(response.parsed_body["data"].size).to eq(20)

      with_tenant(world.organization) { Appointments::AppointmentService.delete_all && Appointments::Appointment.delete_all }
      fill_week(200)
      many = queries_for_agenda

      expect(response.parsed_body["data"].size).to eq(200)
      expect(many).to eq(few)
    end

    it "responde en menos de 150 ms (medido tras calentar)" do
      fill_week(200)
      agenda

      expect(elapsed_seconds { agenda }).to be < 0.15
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
