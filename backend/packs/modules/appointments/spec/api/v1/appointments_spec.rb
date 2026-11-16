require "swagger_helper"

# Booking from the panel at a BRANCH. The permission is `appointments.appointment.create` at the branch and it is asked FIRST (before
# the idempotency key and before any validation). rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: reserva de citas" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let("Idempotency-Key") { SecureRandom.uuid }
  let!(:signed_in) { sign_in(receptionist) }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 30, price_minor: 20_000) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:customer) { create_in(world.organization, :customer, company: world.company_a) }
  # Monday 16 Nov 2026, 10:00 in America/Managua (UTC-6).
  let(:starts_at) { "2026-11-16T10:00:00-06:00" }
  let(:body) { { customer_id: customer.id, service_ids: [ service.id ], professional_id: professional.id, starts_at:, notes: "Primera visita" } }

  let!(:scenario) do
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  before { travel_to Time.utc(2026, 11, 11, 12) }

  after { travel_back }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Appointment" } } }

  def collection_path = "/api/v1/organizations/#{organization_id}/companies/#{company_id}/appointments/branches/#{branch_id}/appointments"
  def stored = with_tenant(world.organization) { Appointments::Appointment.order(:id).to_a }
  def book_slot!(starts_at: Time.utc(2026, 11, 16, 16)) = create_in(world.organization, :appointment, professional:, branch: world.branch_a1, starts_at:, ends_at: starts_at + 30.minutes)

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/appointments" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Reserva una cita en la sucursal desde el panel" do
      tags "Citas"
      description "Exige `appointments.appointment.create` en la sucursal (company_manager, branch_manager y receptionist); se comprueba ANTES de la clave y de validar. " \
                  "`Idempotency-Key` es obligatoria. Solo un profesional concreto: `professional_id` es el del hueco que mostró la disponibilidad, y `any` responde 422 " \
                  "(`appointments.booking_invalid`, `professional_id: any_not_allowed`). `starts_at` es ISO 8601 con zona horaria y debe ser un inicio que el motor ofrezca " \
                  "(rejilla, horarios y ausencias); el panel no aplica la anticipación mínima ni la máxima. El recurso lo asigna el motor. " \
                  "Un hueco ya ocupado, aunque sea por la carrera de otra petición, responde 409 `appointments.slot_unavailable`; la misma persona (usuario) ocupada en otra " \
                  "empresa del grupo, 409 `appointments.person_unavailable`. Un 409 de agenda no consume la clave: se puede reintentar con la misma. " \
                  "El precio de cada servicio queda congelado en la cita. `notes` (hasta 500 caracteres) se guarda cifrada y no se devuelve en la respuesta."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKeyRequired"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/AppointmentInput" }

      response "201", "la cita creada, con el snapshot de precios y sin datos personales del cliente" do
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("branch_id" => branch_id, "professional_id" => professional.id, "customer_id" => customer.id, "status" => "scheduled", "source" => "panel",
                                  "starts_at" => "2026-11-16T16:00:00.000Z", "ends_at" => "2026-11-16T16:30:00.000Z", "total_price_minor" => 20_000, "currency" => "NIO")
          expect(data["services"]).to eq([ { "service_id" => service.id, "position" => 0, "duration_minutes" => 30, "price_minor" => 20_000, "currency" => "NIO" } ])
          expect(stored.map(&:id)).to eq([ data["id"] ])
        end
      end

      response "400", "sin `Idempotency-Key` (`idempotency.key_required`)" do
        schema "$ref" => "#/components/schemas/Problem"

        # rswag always sends the declared header (an empty one is `key_invalid`), so the request without it is made by hand.
        it "responde 400 idempotency.key_required y no crea nada" do
          post collection_path, params: body, headers: { "X-CSRF-Token" => signed_in.csrf_token }, as: :json

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body["code"]).to eq("idempotency.key_required")
          expect(stored).to be_empty
        end
      end

      response "400", "un `starts_at` sin zona horaria" do
        let(:starts_at) { "2026-11-16T10:00:00" }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("request.bad_request")
          expect(stored).to be_empty
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "el rol `professional` no tiene `appointments.appointment.create`; no consume la clave" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored).to be_empty
          expect(with_tenant(world.organization) { Idempotency::Key.count }).to eq(0)
        end
      end

      response "404", "una sucursal de otra empresa" do
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "un profesional que no está asignado a la sucursal" do
        let(:body) { super().merge(professional_id: create_in(world.organization, :professional, company: world.company_a).id) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "409", "el hueco ya está ocupado (`appointments.slot_unavailable`)" do
        let!(:taken) { book_slot! }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("appointments.slot_unavailable")
          expect(stored.map(&:id)).to eq([ taken.id ])
        end
      end

      response "409", "la misma persona está ocupada en otra empresa del grupo (`appointments.person_unavailable`)" do
        let(:person) do
          create(:user).tap do |user|
            user_with_role("receptionist", world, branch: world.branch_a1, user:)
            user_with_role("receptionist", world, branch: world.branch_b1, user:)
          end
        end
        let(:professional) { create_in(world.organization, :professional, company: world.company_a, user_id: person.id) }
        let!(:elsewhere) do
          other = create_in(world.organization, :professional, company: world.company_b, user_id: person.id)
          create_in(world.organization, :appointment, professional: other, branch: world.branch_b1, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30))
        end
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("appointments.person_unavailable")
          expect(stored.map(&:id)).to eq([ elsewhere.id ])
        end
      end

      response "409", "la misma `Idempotency-Key` con otro cuerpo (`idempotency.key_reused`)" do
        let!(:first_booking) do
          post collection_path, params: body.merge(notes: "Otra"), headers: { "X-CSRF-Token" => signed_in.csrf_token, "Idempotency-Key" => send("Idempotency-Key") }, as: :json
        end

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("idempotency.key_reused") }
      end

      response "422", "`professional_id` `any` no se acepta al reservar (`appointments.booking_invalid`)" do
        let(:body) { super().merge(professional_id: "any") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("appointments.booking_invalid")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "professional_id", "code" => "any_not_allowed"))
          expect(stored).to be_empty
        end
      end

      response "422", "un cliente que no es de la empresa (`appointments.booking_invalid`)" do
        let(:customer) { create_in(world.organization, :customer, company: world.company_b) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "customer_id", "code" => "invalid")) }
      end

      response "422", "el pedido no es atendible: un profesional que no ofrece el servicio (`appointments.availability_invalid`)" do
        let!(:unoffered) { create_in(world.organization, :service, company: world.company_a) }
        let(:body) { super().merge(service_ids: [ unoffered.id ]) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("appointments.availability_invalid")
          expect(stored).to be_empty
        end
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
