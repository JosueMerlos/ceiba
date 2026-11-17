require "swagger_helper"

# The appointment lifecycle from the panel: the agenda listing, the detail with notes, editing the notes and the status actions. The
# appointment is always searched among the route branch's (another branch's or company's is a 404). rswag requires the `let` to be
# named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: ciclo de vida de la cita" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:signed_in) { sign_in(receptionist) }
  let!(:modules_enabled) { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }

  let!(:scenario) do
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  # Monday 16 Nov 2026, 10:00 in America/Managua (UTC-6); the clock is frozen on the 11th.
  let(:booked) do
    with_tenant(world.organization) do
      Appointments::Book.call(company: world.company_a, branch: world.branch_a1, customer_id: customer.id, services: [ service ],
                              professional: Appointments::Availability::ProfessionalChoice.of(professional), starts_at: Time.utc(2026, 11, 16, 16),
                              source: "panel", notes: "Trae su tinte")
    end
  end
  let(:appointment_id) { booked.id }

  before { travel_to Time.utc(2026, 11, 11, 12) }

  after { travel_back }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Appointment" } } }
  detail_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/AppointmentDetail" } } }
  list_schema = { type: :object, required: %w[data], additionalProperties: false,
                  properties: { data: { type: :array, items: { "$ref" => "#/components/schemas/Appointment" } } } }

  def set_status(status)
    columns = status == "cancelled" ? { cancelled_by: "staff", cancellation_reason: "other" } : {}
    with_tenant(world.organization) { Appointments::Appointment.where(id: booked.id).update_all(status:, **columns) }
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Agenda: las citas de la sucursal entre dos fechas locales" do
      tags "Citas"
      description "Exige `appointments.appointment.read` en la sucursal, o `appointments.appointment.read_own` (el profesional), que solo ve sus propias citas. " \
                  "`from` y `to` son fechas locales de la sucursal (incluidas), hasta 31 días. Todas las citas en cualquier estado, ordenadas por `starts_at`. " \
                  "Sin paginar: por encima de #{Appointments::Agenda::LIMIT} citas responde 422 (`appointments.agenda_invalid`, `too_many_appointments`) en vez de truncar. " \
                  "Sin notas ni datos del cliente."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :from, in: :query, required: true, schema: { type: :string, format: :date }, description: "Primer día (local), `YYYY-MM-DD`"
      parameter name: :to, in: :query, required: true, schema: { type: :string, format: :date }, description: "Último día (local), `YYYY-MM-DD`"
      parameter name: :professional_id, in: :query, required: false, schema: { type: :string, format: :uuid }, description: "Solo las de ese profesional"

      let(:from) { "2026-11-16" }
      let(:to) { "2026-11-22" }

      response "200", "las citas del rango" do
        let!(:listed) { booked }

        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ booked.id ]) }
      end

      response "400", "sin `from`" do
        let(:from) { nil }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("request.invalid") }
      end

      response "403", "sin permiso de lectura de citas" do
        let!(:signed_in) { sign_in(user_with_role("org_owner", world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "422", "un rango de más de 31 días (`appointments.agenda_invalid`)" do
        let(:to) { "2026-12-31" }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "to", "code" => "too_far")) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments/{appointment_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :appointment_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Detalle de una cita, con sus notas" do
      tags "Citas"
      description "Exige poder editar la cita: `appointments.appointment.update` en la sucursal, o `appointments.appointment.update_own` si es una cita propia " \
                  "(el profesional vinculado al usuario y asignado a la sucursal). Incluye `notes`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la cita con sus notas" do
        schema detail_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => booked.id, "notes" => "Trae su tinte") }
      end

      response "404", "una cita de otra sucursal" do
        let(:appointment_id) { create_in(world.organization, :appointment, professional:, branch: world.branch_a2, starts_at: Time.utc(2026, 11, 17, 16)).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end

    patch "Edita las notas de una cita" do
      tags "Citas"
      description "Mismo permiso que el detalle. `lock_version` es obligatorio: si la cita cambió desde que se leyó (otra edición o un cambio de estado), 409 `resource.stale`. " \
                  "Las notas de una cita reprogramada se editan en la cita nueva (409 `appointments.invalid_transition`). Unas notas de más de 500 caracteres son " \
                  "la validación genérica de una edición (422 `validation.failed`), no el `appointments.booking_invalid` de la reserva."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/AppointmentNotesInput" }

      let(:body) { { notes: "Alérgica al látex", lock_version: 0 } }

      response "200", "las notas guardadas y la versión nueva" do
        schema detail_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("notes" => "Alérgica al látex", "lock_version" => 1) }
      end

      response "409", "una versión vieja (`resource.stale`)" do
        let!(:changed) { set_status("confirmed") && with_tenant(world.organization) { Appointments::Appointment.where(id: booked.id).update_all(lock_version: 1) } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.stale") }
      end

      response "409", "una cita reprogramada (`appointments.invalid_transition`)" do
        let!(:prepared) { set_status("rescheduled") }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("appointments.invalid_transition") }
      end

      response "422", "notas de más de 500 caracteres" do
        let(:body) { { notes: "x" * 501, lock_version: 0 } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("validation.failed") }
      end
    end
  end

  {
    "confirm" => [ "Confirma una cita", "scheduled", "confirmed", "completed" ],
    "check_in" => [ "Registra la llegada del cliente (check-in)", "confirmed", "checked_in", "cancelled" ],
    "complete" => [ "Completa una cita con check-in", "checked_in", "completed", "scheduled" ],
    "no_show" => [ "Marca que el cliente no se presentó (solo después del inicio)", "scheduled", "no_show", "completed" ]
  }.each do |action, (summary, from, to, blocked)|
    path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments/{appointment_id}/#{action}" do
      parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
      parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
      parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
      parameter name: :appointment_id, in: :path, schema: { type: :string, format: :uuid }, required: true

      post summary do
        tags "Citas"
        description "Exige `appointments.appointment.update` en la sucursal, o `appointments.appointment.update_own` si la cita es propia. Desde `#{from}`" \
                    "#{action == 'check_in' ? ' o `scheduled`' : ''}#{action == 'no_show' ? ' o `confirmed`' : ''} pasa a `#{to}`; desde cualquier otro estado, " \
                    "409 `appointments.invalid_transition` (`status: not_allowed`)#{action == 'no_show' ? '; antes de la hora de inicio, `status: too_early`' : ''}. " \
                    "Sube `lock_version` y publica el evento del cambio. `Idempotency-Key` es opcional."
        produces "application/json", "application/problem+json"
        security [ { cookieAuth: [] } ]
        parameter "$ref" => "#/components/parameters/IdempotencyKey"
        parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

        let("Idempotency-Key") { SecureRandom.uuid }

        response "200", "la cita en `#{to}`" do
          let!(:prepared) do
            set_status(from)
            travel_to Time.utc(2026, 11, 16, 16, 10) if action == "no_show"
          end

          let!(:signed_in) { action == "no_show" ? nil : sign_in(receptionist) }
          let("X-CSRF-Token") { (signed_in || sign_in(receptionist)).csrf_token }
          schema single_schema

          run_test! { |response| expect(response.parsed_body["data"]).to include("id" => booked.id, "status" => to) }
        end

        response "403", "un profesional sobre una cita ajena" do
          let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
        end

        response "409", "desde `#{blocked}` (`appointments.invalid_transition`)" do
          let!(:prepared) { set_status(blocked) }

          schema "$ref" => "#/components/schemas/ValidationProblem"

          run_test! { |response| expect(response.parsed_body).to include("code" => "appointments.invalid_transition") }
        end
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments/{appointment_id}/cancel" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :appointment_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Cancela una cita" do
      tags "Citas"
      description "Exige `appointments.appointment.update` en la sucursal (el profesional no cancela, ni siquiera las propias). Desde `scheduled` o `confirmed`; " \
                  "libera el hueco. `reason` es un código de la lista cerrada; queda `cancelled_by: staff`. `Idempotency-Key` es opcional."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/AppointmentCancelInput" }

      let("Idempotency-Key") { SecureRandom.uuid }
      let(:body) { { reason: "customer_request" } }

      response "200", "la cita cancelada" do
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("status" => "cancelled", "cancelled_by" => "staff", "cancellation_reason" => "customer_request")
        end
      end

      response "409", "una cita completada (`appointments.invalid_transition`)" do
        let!(:prepared) { set_status("completed") }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("appointments.invalid_transition") }
      end

      response "422", "un motivo fuera de la lista (`appointments.cancellation_invalid`)" do
        let(:body) { { reason: "otro" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("appointments.cancellation_invalid") }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments/{appointment_id}/reschedule" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :appointment_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Reprograma una cita" do
      tags "Citas"
      description "Exige `appointments.appointment.update` en la sucursal y `Idempotency-Key`. La cita (`scheduled` o `confirmed`) pasa a `rescheduled` y se reserva " \
                  "una nueva enlazada (`rescheduled_from_id`) en la misma transacción, con el mismo cliente, servicios, notas y precio por servicio de la original " \
                  "y la duración actual del catálogo. El nuevo hueco se valida como una reserva del panel: ocupado, 409 `appointments.slot_unavailable` y la original no " \
                  "cambia; si otra petición ya la reprogramó, 409 `appointments.invalid_transition`. Un 409 no consume la clave. " \
                  "Sin `professional_id` se usa el de la cita; si ya no está asignado a la sucursal, 422 `appointments.availability_invalid` " \
                  "(`professional_id: not_assigned`). Como la reserva nueva se valida igual que un `POST` de reserva, un servicio archivado o un cliente " \
                  "inactivo desde la reserva original responden 422 `appointments.availability_invalid` (`service_ids`) o `appointments.booking_invalid` (`customer_id`)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKeyRequired"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/AppointmentRescheduleInput" }

      let("Idempotency-Key") { SecureRandom.uuid }
      let(:body) { { starts_at: "2026-11-16T11:00:00-06:00" } }

      response "201", "la cita nueva" do
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("rescheduled_from_id" => booked.id, "status" => "scheduled", "starts_at" => "2026-11-16T17:00:00.000Z")
        end
      end

      response "409", "el nuevo hueco está ocupado (`appointments.slot_unavailable`)" do
        let!(:taken) do
          booked
          create_in(world.organization, :appointment, professional:, branch: world.branch_a1, starts_at: Time.utc(2026, 11, 16, 17))
        end

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("appointments.slot_unavailable") }
      end

      response "409", "ya estaba reprogramada (`appointments.invalid_transition`)" do
        let!(:prepared) { set_status("rescheduled") }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("appointments.invalid_transition") }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
