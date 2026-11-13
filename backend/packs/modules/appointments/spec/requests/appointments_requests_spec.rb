require "rails_helper"

# Behavior of POST .../branches/:branch_id/appointments that the contract spec does not describe: idempotency, the order of the
# checks and what a conflict does to the key.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe "Reserva de citas: peticiones" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let!(:signed_in) { sign_in(receptionist) }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }
  # Monday 16 Nov 2026, 10:00 in America/Managua (UTC-6).
  let(:starts_at) { "2026-11-16T10:00:00-06:00" }
  let(:body) { { customer_id: customer.id, service_ids: [ service.id ], professional_id: professional.id, starts_at:, notes: "Llega con su hijo" } }
  let(:key) { SecureRandom.uuid }

  before do
    travel_to Time.utc(2026, 11, 11, 12)
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  after { travel_back }

  def path(branch: world.branch_a1, company: world.company_a)
    "/api/v1/organizations/#{world.organization.id}/companies/#{company.id}/appointments/branches/#{branch.id}/appointments"
  end

  def book(params = body, idempotency_key: key, csrf: signed_in.csrf_headers, **target)
    headers = idempotency_key ? csrf.merge("Idempotency-Key" => idempotency_key) : csrf
    post path(**target), params:, headers:, as: :json
  end

  def appointments = with_tenant(world.organization) { Appointments::Appointment.order(:id).to_a }
  def snapshot_lines = with_tenant(world.organization) { Appointments::AppointmentService.count }
  def keys_stored = with_tenant(world.organization) { Idempotency::Key.where(key:).count }

  describe "una reserva válida" do
    it "responde 201 con la cita, su snapshot de precios y sin datos personales del cliente", :aggregate_failures do
      book

      expect(response).to have_http_status(:created)
      data = response.parsed_body.fetch("data")
      stored = appointments.sole
      expect(data).to eq(
        "id" => stored.id, "branch_id" => world.branch_a1.id, "professional_id" => professional.id, "resource_id" => nil, "customer_id" => customer.id,
        "starts_at" => "2026-11-16T16:00:00.000Z", "ends_at" => "2026-11-16T16:30:00.000Z", "status" => "scheduled", "source" => "panel",
        "lock_version" => 0, "notes" => "Llega con su hijo", "total_price_minor" => 20_000, "currency" => "NIO",
        "services" => [ { "service_id" => service.id, "position" => 0, "duration_minutes" => 30, "price_minor" => 20_000, "currency" => "NIO" } ]
      )
      expect(snapshot_lines).to eq(1)
      expect(stored).to have_attributes(created_by_type: "user", source: "panel")
    end

    it "una reserva del panel puede caer dentro de la anticipación mínima" do
      travel_to Time.utc(2026, 11, 16, 15, 30)

      book(csrf: sign_in(receptionist).csrf_headers)

      expect(response).to have_http_status(:created)
    end
  end

  describe "Idempotency-Key" do
    it "sin la cabecera responde 400 idempotency.key_required y no crea nada", :aggregate_failures do
      book(idempotency_key: nil)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("code" => "idempotency.key_required")
      expect(appointments).to be_empty
    end

    it "repetir la petición con la misma clave devuelve el mismo estado y cuerpo, marca el replay y deja una sola cita", :aggregate_failures do
      book
      first = [ response.status, response.body ]

      book

      expect([ response.status, response.body ]).to eq(first)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(appointments.size).to eq(1)
    end

    it "la misma clave con otro cuerpo responde 409 idempotency.key_reused", :aggregate_failures do
      book
      book(body.merge(notes: "Otra nota"))

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include("code" => "idempotency.key_reused")
      expect(appointments.size).to eq(1)
    end
  end

  describe "autorización y alcance" do
    it "un rol sin appointments.appointment.create en esa sucursal recibe 403 y no consume la clave", :aggregate_failures do
      without_permission = sign_in(user_with_role("professional", world, branch: world.branch_a1))

      book(csrf: without_permission.csrf_headers)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("code" => "access.forbidden")
      expect(keys_stored).to eq(0)
      expect(appointments).to be_empty
    end

    it "una repetición con la misma clave responde 403 si al usuario ya le quitaron el permiso", :aggregate_failures do
      writer = user_with_custom_role(world, scope_level: "branch", branch: world.branch_a1, permissions: %w[appointments.appointment.create])
      csrf = sign_in(writer).csrf_headers
      book(csrf:)
      expect(response).to have_http_status(:created)
      Access::RolePermission.where(permission_key: "appointments.appointment.create").delete_all

      book(csrf:)

      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
      expect(appointments.size).to eq(1)
    end

    it "una sucursal de otra empresa responde 404", :aggregate_failures do
      book(branch: world.branch_b1, company: world.company_a)

      expect(response).to have_http_status(:not_found)
      expect(appointments).to be_empty
    end
  end

  describe "tipos y recursos del cuerpo" do
    it "un starts_at sin zona horaria responde 400", :aggregate_failures do
      book(body.merge(starts_at: "2026-11-16T10:00:00"))

      expect(response).to have_http_status(:bad_request)
      expect(appointments).to be_empty
    end

    it "un starts_at sin segundos responde 400", :aggregate_failures do
      book(body.merge(starts_at: "2026-11-16T10:00-06:00"))

      expect(response).to have_http_status(:bad_request)
      expect(appointments).to be_empty
    end

    it "un starts_at con una fecha que no existe (30 de febrero) responde 400 como cualquier instante mal formado", :aggregate_failures do
      book(body.merge(starts_at: "2026-02-30T10:00:00-06:00"))

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("code" => "request.bad_request")
      expect(appointments).to be_empty
    end

    it "un starts_at con una fracción de segundo distinta de cero responde 422 booking_invalid con starts_at not_on_minute", :aggregate_failures do
      book(body.merge(starts_at: "2026-11-16T10:00:00.5-06:00"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "starts_at", "code" => "not_on_minute"))
      expect(appointments).to be_empty
    end

    it "un starts_at con fracción en cero (.000) se acepta" do
      book(body.merge(starts_at: "2026-11-16T10:00:00.000-06:00"))

      expect(response).to have_http_status(:created)
    end

    [ "2026-11-08T10:00:00-06:00", "2026-11-10T10:00:00-06:00", "2026-11-11T11:59:00Z" ].each do |past|
      it "un starts_at en el pasado (#{past}) responde 422 booking_invalid con starts_at in_the_past y un mensaje es-NI", :aggregate_failures do
        book(body.merge(starts_at: past))

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to include("code" => "appointments.booking_invalid")
        expect(response.parsed_body["errors"]).to eq([ { "field" => "starts_at", "code" => "in_the_past", "message" => "la hora de inicio ya pasó" } ])
        expect(appointments).to be_empty
      end
    end

    it "un service_ids que no es una lista de UUID responde 400" do
      book(body.merge(service_ids: "no-es-lista"))

      expect(response).to have_http_status(:bad_request)
    end

    it "un servicio inexistente responde 404 y uno de otra empresa también" do
      foreign = create_in(world.organization, :service, company: world.company_b)

      book(body.merge(service_ids: [ foreign.id ]))

      expect(response).to have_http_status(:not_found)
    end

    it "un profesional que no está asignado a la sucursal responde 404" do
      unassigned = create_in(world.organization, :professional, company: world.company_a)

      book(body.merge(professional_id: unassigned.id))

      expect(response).to have_http_status(:not_found)
    end

    it "professional_id any responde 422 booking_invalid con professional_id any_not_allowed", :aggregate_failures do
      book(body.merge(professional_id: "any"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("code" => "appointments.booking_invalid")
      expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "professional_id", "code" => "any_not_allowed"))
      expect(appointments).to be_empty
    end

    it "un cliente de otra empresa responde 422 booking_invalid" do
      foreign = create_in(world.organization, :customer, company: world.company_b)

      book(body.merge(customer_id: foreign.id))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "customer_id", "code" => "invalid"))
    end
  end

  describe "un hueco ocupado" do
    let!(:taken) { create_in(world.organization, :appointment, professional:, branch: world.branch_a1, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30)) }

    it "responde 409 appointments.slot_unavailable en problem+json y no consume la clave", :aggregate_failures do
      book

      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("code" => "appointments.slot_unavailable", "status" => 409)
      expect(appointments.size).to eq(1)
      expect(keys_stored).to eq(0)
    end

    it "reintentar con la misma clave cuando el hueco se libera crea la cita", :aggregate_failures do
      book
      expect(response).to have_http_status(:conflict)
      with_tenant(world.organization) { taken.update!(status: "cancelled") }

      book

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotency-Replayed"]).to be_nil
      expect(appointments.count { it.status == "scheduled" }).to eq(1)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
