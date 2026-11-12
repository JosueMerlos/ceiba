require "swagger_helper"

# Free slots of one professional for one service at a BRANCH. The permission is `appointments.appointment.create` at the branch
# and it is asked FIRST, so a role without it gets a 403 before any validation or lookup (no oracle over professional and
# service ids). The professional is searched among the ones assigned to the route's branch, the service among the company's.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: disponibilidad" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:signed_in) { sign_in(receptionist) }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  # Monday 16 Nov 2026; the branch is in America/Managua (UTC-6, no DST): 09:00 local is 15:00Z.
  let(:monday) { "2026-11-16" }
  let(:from) { monday }
  let(:to) { monday }
  let(:service_ids) { service.id }
  let(:professional_id) { professional.id }

  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 45) }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let!(:scenario) do
    create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
    create_in(world.organization, :professional_service, professional:, service:)
    create_in(world.organization, :branch_service_override, service:, branch: world.branch_a1, duration_minutes: 30)
    # Enabling the module gave the branch its default week; this scenario owns the hours.
    with_tenant(world.organization) { Appointments::WeeklySchedule.where(branch_id: world.branch_a1.id, owner_type: "branch").delete_all }
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
    create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional:, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
  end

  before { travel_to Time.utc(2026, 11, 11, 12) }

  after { travel_back }

  slot_schema = {
    type: :object, required: %w[data meta], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/AvailabilitySlot" } },
      meta: {
        type: :object, required: %w[time_zone duration_minutes buffer_before_minutes buffer_after_minutes price step_minutes], additionalProperties: false, properties: {
          time_zone: { type: :string }, duration_minutes: { type: :integer }, buffer_before_minutes: { type: :integer }, buffer_after_minutes: { type: :integer },
          price: { "$ref" => "#/components/schemas/AvailabilityPrice" }, step_minutes: { type: :integer }
        }
      }
    }
  }

  def book(starts_at, minutes: 30)
    create_in(world.organization, :appointment, professional:, branch: world.branch_a1, starts_at:, ends_at: starts_at + minutes.minutes)
  end

  def starts_of(response) = response.parsed_body["data"].pluck("starts_at")

  # rswag builds one value per parameter, so a repeated one needs a hand-written query string.
  describe "un parámetro de consulta repetido" do
    let(:base) { { service_ids:, professional_id:, from:, to: } }
    let(:path) { "/api/v1/organizations/#{organization_id}/companies/#{company_id}/appointments/branches/#{branch_id}/availability" }

    %i[service_ids professional_id from to].each do |name|
      it "`#{name}` dos veces es un 400 request.bad_request (no gana el último)", :aggregate_failures do
        query = base.map { |key, value| "#{key}=#{value}" }.join("&") + "&#{name}=#{base[name]}"

        get "#{path}?#{query}"

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include("code" => "request.bad_request")
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/availability" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Consulta los horarios libres de uno o varios servicios, con un profesional o con cualquiera" do
      tags "Disponibilidad"
      description "Exige `appointments.appointment.create` en la sucursal (company_manager, branch_manager y receptionist); se comprueba ANTES de validar. " \
                  "`from` y `to` son fechas locales de la sucursal (`YYYY-MM-DD`, inclusivas, `from <= to`, hasta 31 días). `service_ids` son de 1 a 5 servicios de la empresa (404 si alguno no existe), " \
                  "en orden de secuencia; `professional_id` es un profesional asignado a la sucursal o el literal `any`. Devuelve los inicios posibles en la rejilla del reloj local (múltiplos del " \
                  "paso `slot_step_minutes` desde la medianoche local) con la duración efectiva del servicio en la sucursal; los instantes son UTC. " \
                  "La agenda del profesional es única: sus citas y ausencias de otras sucursales también restan, y solo se expone libre/ocupado. " \
                  "Parámetro ausente: 400 `request.invalid`; mal formado: 400 `request.bad_request`; pedido no atendible: 422 `appointments.availability_invalid`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :service_ids, in: :query, schema: { type: :string }, required: true, description: "Servicios de la empresa, UUID separados por comas (1 a 5, sin repetir); el orden es la secuencia"
      parameter name: :professional_id, in: :query, schema: { type: :string, format: :uuid }, required: true, description: "Profesional asignado a la sucursal"
      parameter name: :from, in: :query, schema: { type: :string, format: :date }, required: true, description: "Primer día local (`YYYY-MM-DD`)"
      parameter name: :to, in: :query, schema: { type: :string, format: :date }, required: true, description: "Último día local, inclusivo (`YYYY-MM-DD`)"

      response "200", "horario 9-13, cita 10:00-10:30 y duración de la sucursal de 30: ningún hueco solapa la cita" do
        let!(:booking) { book(Time.utc(2026, 11, 16, 16)) }

        schema slot_schema

        run_test! do |response|
          local = %w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30]
          expected = local.map { |hhmm| Time.find_zone("America/Managua").parse("2026-11-16 #{hhmm}").utc.iso8601(3) }

          expect(starts_of(response)).to eq(expected)
          expect(response.parsed_body["data"].first).to eq("starts_at" => "2026-11-16T15:00:00.000Z", "ends_at" => "2026-11-16T15:30:00.000Z",
                                                           "professional_id" => professional.id, "resource_id" => nil)
          expect(response.parsed_body["meta"]).to eq("time_zone" => "America/Managua", "duration_minutes" => 30, "buffer_before_minutes" => 0, "buffer_after_minutes" => 0,
                                                     "price" => { "amount_minor" => 20_000, "currency" => "NIO" }, "step_minutes" => 15)
        end
      end

      response "200", "dos servicios en secuencia: duración y precio sumados, el override de la sucursal solo en el servicio que lo tiene" do
        let(:second) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 20, price_minor: 5_000, buffer_before_minutes: 5, buffer_after_minutes: 10) }
        let(:service_ids) { "#{service.id},#{second.id}" }
        let!(:both) { create_in(world.organization, :professional_service, professional:, service: second) }

        schema slot_schema

        run_test! do |response|
          expect(response.parsed_body["meta"]).to include("duration_minutes" => 50, "buffer_before_minutes" => 0, "buffer_after_minutes" => 10,
                                                          "price" => { "amount_minor" => 25_000, "currency" => "NIO" })
          expect(response.parsed_body["data"].first).to include("starts_at" => "2026-11-16T15:00:00.000Z", "ends_at" => "2026-11-16T15:50:00.000Z")
        end
      end

      response "200", "`professional_id=any` asigna un profesional a cada hueco" do
        let(:professional_id) { "any" }
        let!(:other) do
          create_in(world.organization, :professional, company: world.company_a).tap do |pro|
            create_in(world.organization, :professional_branch_assignment, professional: pro, branch: world.branch_a1)
            create_in(world.organization, :professional_service, professional: pro, service:)
            create_in(world.organization, :weekly_schedule, branch: world.branch_a1, professional: pro, weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00")
          end
        end

        schema slot_schema

        run_test! do |response|
          slots = response.parsed_body["data"]

          expect(slots.pluck("professional_id").uniq).to all(be_in([ professional.id, other.id ]))
          expect(slots.pluck("starts_at")).to eq(slots.pluck("starts_at").uniq.sort)
          expect(slots.first).to include("starts_at" => "2026-11-16T15:00:00.000Z")
        end
      end

      response "200", "la cita de OTRA sucursal del mismo profesional también resta (agenda única)" do
        let!(:other_branch_booking) do
          other = create_in(world.organization, :branch, company: world.company_a)
          create_in(world.organization, :professional_branch_assignment, professional:, branch: other)
          create_in(world.organization, :appointment, professional:, branch: other, starts_at: Time.utc(2026, 11, 16, 16), ends_at: Time.utc(2026, 11, 16, 16, 30))
        end

        schema slot_schema

        run_test! do |response|
          local = %w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30]
          expected = local.map { |hhmm| Time.find_zone("America/Managua").parse("2026-11-16 #{hhmm}").utc.iso8601(3) }

          expect(starts_of(response)).to eq(expected)
        end
      end

      response "200", "un día sin horario devuelve una lista vacía" do
        let(:from) { "2026-11-17" }
        let(:to) { "2026-11-17" }

        schema slot_schema

        run_test! { |response| expect(response.parsed_body["data"]).to eq([]) }
      end

      [ "2026-13-01", "2026-11-1", "16/11/2026", "2026-02-30" ].each do |bad|
        response "400", "una fecha mal formada (#{bad})" do
          let(:from) { bad }

          schema "$ref" => "#/components/schemas/Problem"

          run_test! { |response| expect(response.parsed_body).to include("code" => "request.bad_request") }
        end
      end

      response "400", "un `professional_id` que no es un UUID" do
        let(:professional_id) { "no-es-un-uuid" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "request.bad_request") }
      end

      response "400", "un `service_ids` con un elemento que no es un UUID" do
        let(:service_ids) { "#{service.id},123" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "request.bad_request") }
      end

      response "400", "un `professional_id` que no es UUID ni `any`" do
        let(:professional_id) { "ANY" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "request.bad_request") }
      end

      response "422", "un servicio repetido en `service_ids`" do
        let(:service_ids) { "#{service.id},#{service.id}" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "service_ids", "code" => "duplicated")) }
      end

      response "422", "más de 5 servicios" do
        let(:service_ids) { Array.new(6) { create_in(world.organization, :service, company: world.company_a).id }.join(",") }
        let(:professional_id) { "any" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "service_ids", "code" => "too_many")) }
      end

      # rswag publishes only the LAST block of a status code: the superset (`errors`) goes last.
      response "400", "sin `from`" do
        let(:from) { nil }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body).to include("code" => "request.invalid")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "from", "code" => "missing"))
        end
      end

      response "400", "sin ningún parámetro de consulta" do
        let(:service_ids) { nil }
        let(:professional_id) { nil }
        let(:from) { nil }
        let(:to) { nil }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "request.invalid") }
      end

      response "422", "`from` posterior a `to`" do
        let(:from) { "2026-11-17" }
        let(:to) { "2026-11-16" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body).to include("code" => "appointments.availability_invalid")
          expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "to", "code" => "invalid_range", "message" => a_kind_of(String)))
        end
      end

      response "422", "un `from` anterior a ayer en la hora local de la sucursal" do
        let(:from) { "2026-11-09" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body).to include("code" => "appointments.availability_invalid")
          expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "from", "code" => "too_early", "message" => a_kind_of(String)))
        end
      end

      response "422", "un rango de más de 31 días" do
        let(:to) { "2026-12-17" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "to", "code" => "invalid_range")) }
      end

      response "200", "un rango de exactamente 31 días" do
        let(:to) { "2026-12-16" }

        schema slot_schema

        run_test!
      end

      response "422", "una sucursal inactiva está cerrada" do
        let!(:closed) { with_tenant(world.organization) { world.branch_a1.update!(status: "inactive") } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "branch_id", "code" => "inactive", "message" => a_kind_of(String))) }
      end

      response "422", "un profesional pausado" do
        let!(:paused) { with_tenant(world.organization) { professional.update!(active: false) } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "professional_id", "code" => "inactive")) }
      end

      response "422", "un profesional archivado" do
        let!(:archived) { with_tenant(world.organization) { professional.update!(archived_at: Time.current) } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "professional_id", "code" => "inactive")) }
      end

      response "422", "un servicio archivado" do
        let!(:archived) { with_tenant(world.organization) { service.update!(archived_at: Time.current) } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "service_ids", "code" => "inactive")) }
      end

      response "422", "varios errores a la vez se devuelven todos" do
        let(:from) { "2026-11-17" }
        let(:to) { "2026-11-16" }
        let!(:paused) { with_tenant(world.organization) { [ professional.update!(active: false), service.update!(active: false) ] } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to contain_exactly(
            a_hash_including("field" => "professional_id", "code" => "inactive"), a_hash_including("field" => "service_ids", "code" => "inactive"),
            a_hash_including("field" => "to", "code" => "invalid_range")
          )
        end
      end

      response "422", "un servicio inactivo" do
        let!(:deactivated) { with_tenant(world.organization) { service.update!(active: false) } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "service_ids", "code" => "inactive")) }
      end

      response "422", "un servicio que el profesional no presta" do
        let(:service_ids) { create_in(world.organization, :service, company: world.company_a).id }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "service_ids", "code" => "not_provided")) }
      end

      response "404", "un profesional de la empresa que no está asignado a la sucursal" do
        let(:professional_id) { create_in(world.organization, :professional, company: world.company_a).id }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "resource.not_found") }
      end

      response "404", "un servicio de otra empresa" do
        let(:service_ids) { create_in(world.organization, :service, company: world.company_b).id }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "resource.not_found") }
      end

      response "404", "un id de profesional que no existe" do
        let(:professional_id) { "0198f0a0-0000-7000-8000-000000000000" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }

        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el rol `professional` no tiene `appointments.appointment.create`" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "access.forbidden") }
      end

      response "403", "sin permiso, la autorización va ANTES de validar: ni un 400 ni un 404 sobre ids ajenos" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        let(:from) { "no-es-fecha" }
        let(:professional_id) { "0198f0a0-0000-7000-8000-000000000000" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "access.forbidden") }
      end

      response "200", "el branch_manager de la sucursal" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }

        schema slot_schema

        run_test!
      end

      response "200", "el company_manager de la empresa" do
        let!(:signed_in) { sign_in(manager) }

        schema slot_schema

        run_test!
      end

      response "404", "un receptionist de una sucursal hermana: la sucursal no es visible para él" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a2)) }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "resource.not_found") }
      end

      response "404", "un usuario de OTRA organización" do
        let!(:signed_in) do
          other = build_access_world
          sign_in(user_with_role("company_manager", other, company: other.company_a))
        end

        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
