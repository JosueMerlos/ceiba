require "rails_helper"

# Criterio 1 de M0.13: la línea de log de una request autenticada es JSON con request_id, organization_id y principal_id,
# y sin correo ni teléfono.
RSpec.describe "Log estructurado de requests" do
  include_context "con endpoints de prueba de la API"
  include TenancyHelpers

  let(:output) { StringIO.new }
  let(:organization) { new_organization }
  let(:user) { create(:user, email: "ana.secreta@ceiba.test", full_name: "Ana Secreta") }
  let(:log_lines) { output.string.lines.filter_map { |line| JSON.parse(line) rescue nil } } # rubocop:disable Style/RescueModifier
  let(:request_line) { log_lines.find { |line| line["controller"] } }

  around do |example|
    logger = ActiveSupport::Logger.new(output)
    logger.formatter = Observability::JsonLogFormatter.new
    original = Lograge.logger
    Lograge.logger = logger
    example.run
  ensure
    Lograge.logger = original
    purge_organizations(organization)
  end

  before { sign_in(user) }

  it "criterio 1: es una línea JSON con request_id, organization_id, principal_id, duración y status" do
    organization # se crea antes de la request
    get "/api/v1/probes/in_context", params: { organization_id: organization.id }

    expect(response).to have_http_status(:ok)
    expect(request_line).to include(
      "method" => "GET", "path" => "/api/v1/probes/in_context", "status" => 200,
      "request_id" => response.headers["X-Request-Id"], "organization_id" => organization.id,
      "company_id" => nil, "branch_id" => nil, "principal_type" => "user", "principal_id" => user.id
    )
    expect(request_line["duration"]).to be_a(Numeric)
  end

  it "criterio 1: no contiene correo, nombre ni teléfono, ni siquiera si llegan por la query string" do
    get "/api/v1/probes/in_context", params: { organization_id: organization.id, phone: "+505 8888 7777", email: "otra@ceiba.test" }

    expect(output.string).not_to include(user.email, "Ana Secreta", "8888", "otra@ceiba.test", "phone", "email")
  end

  it "una request sin sesión también se registra, con el principal vacío" do
    reset!
    get "/api/v1/probes/guarded"

    expect(response).to have_http_status(:unauthorized)
    expect(request_line).to include("status" => 401, "principal_id" => nil, "organization_id" => nil)
  end

  it "registra la IP del cliente como remote_ip" do
    get "/api/v1/probes/in_context", params: { organization_id: organization.id }, headers: { "REMOTE_ADDR" => "203.0.113.9" }

    expect(request_line["remote_ip"]).to eq("203.0.113.9")
  end

  it "las sondas /api/health y /api/ready no generan línea (ruido cada pocos segundos)" do
    get "/api/health"

    expect(request_line).to be_nil
  end
end
