require "rails_helper"

# Criterios 1, 2 y 3 de M0.06 y la tabla de estados de docs/architecture/07-api-contract.md: todo error de la API sale
# como application/problem+json (RFC 9457) con type, title, status, code y request_id, y un 500 NUNCA filtra detalles.
RSpec.describe "Errores de la API (problem+json)" do
  include_context "con endpoints de prueba de la API"

  let(:problem) { response.parsed_body }

  def expect_problem(status:, code:)
    expect(response).to have_http_status(status)
    expect(response.media_type).to eq("application/problem+json")
    expect(problem).to include("status" => Rack::Utils.status_code(status), "code" => code)
    expect(problem.values_at("type", "title", "request_id")).to all(be_present)
  end

  describe "404" do
    it "responde problem+json para un registro inexistente, sin exponer el mensaje de Active Record" do
      get "/api/v1/probes/missing_record"

      expect_problem(status: :not_found, code: "resource.not_found")
      expect(problem["instance"]).to eq("/api/v1/probes/missing_record")
      expect(response.body).not_to include("Couldn't find", ApiProbes::UNKNOWN_ID)
    end

    it "responde problem+json para una ruta de la API que no existe" do
      get "/api/v1/no/existe"

      expect_problem(status: :not_found, code: "route.not_found")
    end

    it "devuelve el mismo request_id en la cabecera X-Request-Id y en el cuerpo" do
      get "/api/v1/probes/missing_record", headers: { "X-Request-Id" => "req-abc-123" }

      expect(problem["request_id"]).to eq("req-abc-123")
      expect(response.headers["X-Request-Id"]).to eq("req-abc-123")
    end

    it "genera un request_id cuando el cliente no manda uno" do
      get "/api/v1/probes/missing_record"

      expect(problem["request_id"]).to eq(response.headers["X-Request-Id"])
    end
  end

  describe "422" do
    it "lista los errores por campo (field, code, message)" do
      get "/api/v1/probes/invalid_record"

      expect_problem(status: :unprocessable_content, code: "validation.failed")
      expect(problem["errors"]).to include(
        a_hash_including("field" => "name", "code" => "blank", "message" => "no puede estar en blanco")
      )
    end

    it "traduce Tenancy::ProvisioningFailed(:slug_reserved) con el campo desglosado" do
      get "/api/v1/probes/slug_reserved"

      expect_problem(status: :unprocessable_content, code: "tenancy.slug_reserved")
      expect(problem["errors"]).to eq([ { "field" => "company.slug", "code" => "invalid", "message" => "está reservado" } ])
    end
  end

  describe "409" do
    it "responde conflicto ante un lock_version viejo (StaleObjectError)" do
      get "/api/v1/probes/stale_record"

      expect_problem(status: :conflict, code: "resource.stale")
    end

    it "responde conflicto ante una violación de unicidad, sin filtrar el SQL ni el nombre del índice" do
      get "/api/v1/probes/duplicate"

      expect_problem(status: :conflict, code: "resource.conflict")
      expect(response.body).not_to include("secret_index", "PG::")
    end

    it "traduce Tenancy::ProvisioningFailed(:slug_taken) a conflicto" do
      get "/api/v1/probes/slug_taken"

      expect_problem(status: :conflict, code: "tenancy.slug_taken")
    end
  end

  describe "400" do
    it "rechaza un parámetro obligatorio ausente" do
      get "/api/v1/probes/missing_param"

      expect_problem(status: :bad_request, code: "request.invalid")
    end

    it "rechaza un JSON mal formado" do
      post "/api/v1/probes/create", params: "{no es json", headers: { "CONTENT_TYPE" => "application/json" }

      expect_problem(status: :bad_request, code: "request.malformed")
    end
  end

  describe "errores de dominio de tenancy" do
    it "traduce InconsistentContext a 404 (no se revela qué entidad es de quién) sin exponer el mensaje" do
      get "/api/v1/probes/inconsistent_context"

      expect_problem(status: :not_found, code: "tenancy.inconsistent_context")
      expect(response.body).not_to include("company-secreta")
    end

    it "deja TenantMismatch como 500: es un bug del servidor, nunca una regla de negocio" do
      get "/api/v1/probes/tenant_mismatch"

      expect_problem(status: :internal_server_error, code: "internal.error")
      expect(response.body).not_to include("organization_id ajeno")
    end
  end

  describe "500" do
    it "responde problem+json sin stacktrace ni detalles internos ante una excepción no controlada" do
      get "/api/v1/probes/boom"

      expect_problem(status: :internal_server_error, code: "internal.error")
      expect(problem.keys).to match_array(%w[type title status code instance request_id])
      expect(response.body).not_to match(/kaboom|secret_path|hunter2|backtrace|\.rb/i)
    end

    it "no filtra el mensaje de una excepción de dominio sin registrar" do
      get "/api/v1/probes/unregistered"

      expect_problem(status: :internal_server_error, code: "internal.error")
      expect(response.body).not_to include("detalle interno")
    end

    it "registra la excepción real en el log con el request_id (para poder investigarla)" do
      allow(Rails.logger).to receive(:error)

      get "/api/v1/probes/boom", headers: { "X-Request-Id" => "req-500" }

      expect(Rails.logger).to have_received(:error).with(a_string_matching(/req-500.*RuntimeError.*kaboom/m))
    end
  end

  describe "registro de errores de dominio" do
    after { Api::ErrorRegistry.unregister(ApiProbes::ProbeDomainError) }

    it "permite registrar una clase con status y code y la traduce" do
      Api::ErrorRegistry.register(ApiProbes::ProbeDomainError, status: :conflict, code: "probe.domain_error")

      get "/api/v1/probes/unregistered"

      expect_problem(status: :conflict, code: "probe.domain_error")
    end

    it "resuelve por la clase más específica (herencia)" do
      parent = Class.new(StandardError)
      child = Class.new(parent)
      Api::ErrorRegistry.register(parent, status: :unprocessable_content, code: "probe.parent")
      Api::ErrorRegistry.register(child, status: :conflict, code: "probe.child")

      expect(Api::ErrorRegistry.resolve(child.new).code).to eq("probe.child")
      expect(Api::ErrorRegistry.resolve(Class.new(parent).new).code).to eq("probe.parent")
    ensure
      Api::ErrorRegistry.unregister(parent)
      Api::ErrorRegistry.unregister(child)
    end

    it "rechaza registrar el mismo código para dos clases (el code es estable y único)" do
      Api::ErrorRegistry.register(ApiProbes::ProbeDomainError, status: :conflict, code: "probe.dup")

      expect { Api::ErrorRegistry.register(Class.new(StandardError), status: :conflict, code: "probe.dup") }
        .to raise_error(ArgumentError, /probe\.dup/)
    end
  end

  describe "las sondas de infraestructura no cambian" do
    it "/api/health sigue respondiendo su JSON simple" do
      get "/api/health"

      expect(response.media_type).to eq("application/json")
    end
  end
end
