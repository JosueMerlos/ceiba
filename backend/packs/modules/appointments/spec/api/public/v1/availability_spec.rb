require "swagger_helper"

# PUBLIC availability: anonymous, by the company's slug. It never shows who or what is booked (only free instants and the ids a
# booking needs). Every closed door (unknown slug, module off, booking disabled in the company or the branch, other company's
# branch, inactive or foreign service, a professional who does not apply) answers the SAME 404, so nothing reveals which door
# was closed. Only a bad date range is a 422.
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API pública v1: disponibilidad" do
  include ActiveSupport::Testing::TimeHelpers

  let(:world) { build_access_world }
  let(:slug) { world.company_a.slug }
  let(:branch_id) { world.branch_a1.id }
  # Monday 16 Nov 2026; the branch is in America/Managua (UTC-6, no DST): 09:00 local is 15:00Z.
  let(:from) { "2026-11-16" }
  let(:to) { "2026-11-16" }
  let(:service) { create_in(world.organization, :service, company: world.company_a, duration_minutes: 45, price_minor: 30_000) }
  let(:service_ids) { service.id }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a, display_name: "Marta Lopez") }
  let(:professional_id) { professional.id }

  let!(:scenario) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
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

  def query(**overrides)
    { branch_id:, service_ids:, professional_id:, from:, to: }.merge(overrides).compact.to_query
  end

  def fetch(slug: self.slug, **overrides) = get("/api/public/v1/c/#{slug}/availability?#{query(**overrides)}")

  def book(starts_at, minutes: 30)
    create_in(world.organization, :appointment, professional:, branch: world.branch_a1, starts_at:, ends_at: starts_at + minutes.minutes)
  end

  def disable_booking(branch: nil)
    with_tenant(world.organization) { Modules::UpdateSettings.call(company: world.company_a, key: "appointments", branch:, settings: { "public_booking_enabled" => false }) }
  end

  describe "una puerta cerrada es siempre el mismo 404" do
    def closed_body
      expect(response).to have_http_status(:not_found)
      response.parsed_body.except("request_id")
    end

    # Each closed door is a way of making the same request fail; the body must not tell them apart.
    {
      "el módulo de citas apagado" => -> { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } },
      "la reserva pública apagada en la empresa (aunque la sucursal diga que sí)" => lambda {
        with_tenant(world.organization) do
          Modules::UpdateSettings.call(company: world.company_a, key: "appointments", branch: world.branch_a1, settings: { "public_booking_enabled" => true })
        end
        disable_booking
      },
      "la reserva pública apagada en la sucursal" => -> { disable_booking(branch: world.branch_a1) },
      "la organización suspendida" => -> { world.organization.update!(status: "suspended") },
      "la empresa inactiva" => -> { with_tenant(world.organization) { world.company_a.update!(status: "inactive") } },
      "la sucursal inactiva" => -> { with_tenant(world.organization) { world.branch_a1.update!(status: "inactive") } }
    }.each do |door, close|
      it "con #{door}" do
        fetch
        open_door = response.parsed_body.except("request_id")
        expect(response).to have_http_status(:ok)

        instance_exec(&close)
        fetch

        expect(closed_body).to eq(open_door.merge("type" => "urn:ceiba:error:resource.not_found", "title" => "No se encontró el recurso", "status" => 404,
                                                   "code" => "resource.not_found", "instance" => "/api/public/v1/c/#{slug}/availability").except("data", "meta"))
      end
    end

    # Things that do not apply to the request, each a way of asking for something the public cannot have.
    def foreign_attempts
      other_service = create_in(world.organization, :service, company: world.company_a)
      inactive = create_in(world.organization, :service, company: world.company_a, active: false)
      create_in(world.organization, :professional_service, professional:, service: inactive)
      unassigned = create_in(world.organization, :professional, company: world.company_a)
      create_in(world.organization, :professional_service, professional: unassigned, service:)
      [ { slug: "no-existe-nunca" }, { branch_id: world.branch_b1.id }, { branch_id: "0198f0a0-0000-7000-8000-000000000000" },
        { service_ids: create_in(world.organization, :service, company: world.company_b).id }, { service_ids: "0198f0a0-0000-7000-8000-000000000000" },
        { service_ids: inactive.id }, { service_ids: "#{service.id},#{other_service.id}" }, { professional_id: unassigned.id },
        { professional_id: "0198f0a0-0000-7000-8000-000000000000" } ]
    end

    it "con un slug desconocido, una sucursal ajena, un servicio ajeno, inactivo o inexistente y un profesional que no aplica: el mismo cuerpo" do
      attempts = foreign_attempts

      bodies = attempts.map do |attempt|
        fetch(**attempt)
        [ response.status, response.parsed_body.except("request_id", "instance") ]
      end

      expect(bodies.uniq).to eq([ [ 404, { "type" => "urn:ceiba:error:resource.not_found", "title" => "No se encontró el recurso", "status" => 404, "code" => "resource.not_found" } ] ])
    end
  end

  describe "lo que un anónimo no ve" do
    it "ni nombres, ni ids de citas: solo el conjunto exacto de claves", :aggregate_failures do
      appointment = book(Time.utc(2026, 11, 16, 16))

      fetch

      body = response.parsed_body
      expect(body.keys).to contain_exactly("data", "meta")
      expect(body["data"]).to all(satisfy { |slot| slot.keys.sort == %w[ends_at professional_id resource_id starts_at] })
      expect(body["meta"].keys).to contain_exactly("time_zone", "duration_minutes", "buffer_before_minutes", "buffer_after_minutes", "price", "step_minutes")
      expect(body["meta"]["price"].keys).to contain_exactly("amount_minor", "currency")
      expect(response.body).not_to include(appointment.id, "Marta", "Lopez", world.branch_a1.name)
    end

    it "no pide ni crea sesión: ni cookie ni cabeceras de sesión" do
      fetch

      expect(response.headers["Set-Cookie"]).to be_nil
    end
  end

  describe "forma de la petición y rango" do
    it "sin `branch_id` es un 400 request.invalid" do
      fetch(branch_id: nil)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("code" => "request.invalid")
    end

    [ { branch_id: "no-es-uuid" }, { service_ids: "123" }, { professional_id: "ANY" }, { from: "2026-13-01" },
      { service_ids: "a,b,c,d,e,f".split(",").map { "0198f0a0-0000-7000-8000-00000000000#{it.ord - 96}" }.join(",") } ].each do |bad|
      it "#{bad.keys.first} mal formado (#{bad.values.first.to_s[0, 20]}) es un 400 request.bad_request" do
        fetch(**bad)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include("code" => "request.bad_request")
      end
    end

    it "un servicio repetido es un 400 request.bad_request (la forma, no un 404)" do
      fetch(service_ids: "#{service.id},#{service.id}")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to include("code" => "request.bad_request")
    end

    it "un parámetro repetido es un 400" do
      get "/api/public/v1/c/#{slug}/availability?#{query}&branch_id=#{branch_id}"

      expect(response).to have_http_status(:bad_request)
    end

    it "la forma mala con el módulo apagado sigue siendo 404: la puerta va antes" do
      with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") }

      fetch(from: "no-es-fecha")

      expect(response).to have_http_status(:not_found)
    end

    # The company-level doors run before the query is read: a malformed query must not tell an existing closed company from an
    # unknown slug.
    {
      "la reserva pública apagada en la empresa" => -> { disable_booking },
      "la empresa inactiva" => -> { with_tenant(world.organization) { world.company_a.update!(status: "inactive") } },
      "la organización suspendida" => -> { world.organization.update!(status: "suspended") }
    }.each do |door, close|
      it "la forma mala con #{door} es 404, igual que un slug desconocido" do
        instance_exec(&close)

        fetch(from: "no-es-fecha")
        closed = [ response.status, response.parsed_body.except("request_id", "instance") ]
        fetch(slug: "no-existe-nunca", from: "no-es-fecha")

        expect(closed).to eq([ 404, response.parsed_body.except("request_id", "instance") ])
        expect(response).to have_http_status(:not_found)
      end
    end

    it "la forma mala en una empresa abierta sigue siendo 400" do
      fetch(from: "no-es-fecha")

      expect(response).to have_http_status(:bad_request)
    end
  end

  path "/api/public/v1/c/{slug}/availability" do
    parameter name: :slug, in: :path, schema: { type: :string, pattern: "^[a-z0-9-]{3,40}$" }, required: true, description: "Slug público de la empresa"

    get "Consulta los horarios libres de una empresa sin sesión" do
      tags "Disponibilidad pública"
      description "Superficie ANÓNIMA: sin sesión ni CSRF. Devuelve los inicios libres (UTC) de uno o varios servicios con un profesional o con `any`, " \
                  "con `professional_id` y `resource_id` asignados y el precio total. No expone nombres ni citas. Rango de hasta 14 días " \
                  "(`from` no anterior a ayer en la hora local de la sucursal). Un slug desconocido, el módulo de citas apagado, la reserva pública " \
                  "apagada (empresa o sucursal), la empresa inactiva, la organización suspendida, una sucursal ajena o inactiva, y un servicio o profesional inexistente, inactivo o que no aplica " \
                  "responden todos el MISMO 404 `resource.not_found`. La respuesta se guarda en caché 30 s y está limitada a 60 peticiones por minuto " \
                  "por IP y empresa (429 `rate_limit.exceeded`)."
      produces "application/json", "application/problem+json"
      security []
      parameter name: :branch_id, in: :query, schema: { type: :string, format: :uuid }, required: true, description: "Sucursal de la empresa"
      parameter name: :service_ids, in: :query, schema: { type: :string }, required: true, description: "Servicios, UUID separados por comas (1 a 5, sin repetir); el orden es la secuencia"
      parameter name: :professional_id, in: :query, schema: { type: :string }, required: true, description: "UUID de un profesional de la sucursal o el literal `any`"
      parameter name: :from, in: :query, schema: { type: :string, format: :date }, required: true, description: "Primer día local (`YYYY-MM-DD`)"
      parameter name: :to, in: :query, schema: { type: :string, format: :date }, required: true, description: "Último día local, inclusivo (`YYYY-MM-DD`)"

      response "200", "horario 9-13, cita 10:00-10:30, duración de la sucursal 30 y precio del servicio: ningún hueco solapa la cita" do
        let!(:booking) { book(Time.utc(2026, 11, 16, 16)) }

        schema slot_schema

        run_test! do |response|
          local = %w[09:00 09:15 09:30 10:30 10:45 11:00 11:15 11:30 11:45 12:00 12:15 12:30]
          expected = local.map { |hhmm| Time.find_zone("America/Managua").parse("2026-11-16 #{hhmm}").utc.iso8601(3) }

          expect(response.parsed_body["data"].pluck("starts_at")).to eq(expected)
          expect(response.parsed_body["data"].first).to eq("starts_at" => "2026-11-16T15:00:00.000Z", "ends_at" => "2026-11-16T15:30:00.000Z",
                                                           "professional_id" => professional.id, "resource_id" => nil)
          expect(response.parsed_body["meta"]).to eq("time_zone" => "America/Managua", "duration_minutes" => 30, "buffer_before_minutes" => 0, "buffer_after_minutes" => 0,
                                                     "price" => { "amount_minor" => 30_000, "currency" => "NIO" }, "step_minutes" => 15)
        end
      end

      response "200", "`professional_id=any` reparte los huecos entre los profesionales libres" do
        let(:professional_id) { "any" }

        schema slot_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("professional_id").uniq).to eq([ professional.id ]) }
      end

      response "200", "un rango de exactamente 14 días" do
        let(:to) { "2026-11-29" }

        schema slot_schema

        run_test!
      end

      response "422", "un rango de 15 días" do
        let(:to) { "2026-11-30" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "to", "code" => "invalid_range")) }
      end

      response "422", "un `from` anterior a ayer" do
        let(:from) { "2026-11-09" }
        let(:to) { "2026-11-09" }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to contain_exactly(a_hash_including("field" => "from", "code" => "too_early")) }
      end

      response "400", "sin `from`" do
        let(:from) { nil }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "request.invalid") }
      end

      response "429", "más de 60 peticiones por minuto desde la misma IP para la misma empresa (rate_limit.exceeded)" do
        # Rate limiting is off in the test environment: it is turned on for this example only, with a limit of one request.
        before do
          Rack::Attack.enabled = true
          Rack::Attack.reset!
          stub_const("ENV", ENV.to_h.merge("RATE_LIMIT_PUBLIC_AVAILABILITY" => "1"))
          fetch
        end

        after do
          Rack::Attack.reset!
          Rack::Attack.enabled = false
        end

        header "Retry-After", schema: { type: :integer }, description: "Segundos hasta que se abre la ventana siguiente"
        header "RateLimit-Limit", schema: { type: :integer }, description: "Peticiones permitidas por ventana"
        header "RateLimit-Remaining", schema: { type: :integer }, description: "Peticiones restantes en la ventana (0)"
        header "RateLimit-Reset", schema: { type: :integer }, description: "Segundos hasta el reinicio de la ventana"

        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body).to include("code" => "rate_limit.exceeded", "status" => 429)
          expect(response.headers).to include("Retry-After" => be_present, "RateLimit-Limit" => "1", "RateLimit-Remaining" => "0", "RateLimit-Reset" => be_present)
        end
      end

      response "404", "slug desconocido, puerta cerrada o recurso que no aplica: siempre el mismo cuerpo" do
        let(:slug) { "no-existe-nunca" }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "resource.not_found") }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
