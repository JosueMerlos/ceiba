require "rails_helper"

# The log line of an authenticated request is JSON with request_id, organization_id and principal_id, and no email or
# phone.
RSpec.describe "Log estructurado de requests" do # rubocop:disable RSpec/MultipleMemoizedHelpers -- the access world, the route and the log capture are the shared setup
  include TenancyHelpers

  let(:output) { StringIO.new }
  let(:world) { build_access_world }
  let(:organization) { world.organization }
  let(:user) { user_with_role("branch_manager", world, branch: world.branch_a1).tap { |u| u.update!(email: "ana.secreta@ceiba.test", full_name: "Ana Secreta") } }
  # The REAL route that resolves the context from the URL (Access::RouteContextResolver) inside a read-only transaction.
  let(:branch_path) { "/api/v1/organizations/#{organization.id}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}" }
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

  before do
    sign_in(user)
    output.truncate(0) # login is logged too: each example looks only at the request it cares about
    output.rewind
  end

  it "criterio 1: es una línea JSON con request_id, organization_id, principal_id, duración y status" do
    get branch_path

    expect(response).to have_http_status(:ok)
    expect(request_line).to include(
      "method" => "GET", "path" => branch_path, "status" => 200,
      "request_id" => response.headers["X-Request-Id"], "organization_id" => organization.id,
      "company_id" => world.company_a.id, "branch_id" => world.branch_a1.id, "principal_type" => "user", "principal_id" => user.id
    )
    expect(request_line["duration"]).to be_a(Numeric)
  end

  it "criterio 1: no contiene correo, nombre ni teléfono, ni siquiera si llegan por la query string" do
    get branch_path, params: { phone: "+505 8888 7777", email: "otra@ceiba.test" }

    expect(output.string).not_to include(user.email, "Ana Secreta", "8888", "otra@ceiba.test", "phone", "email")
  end

  it "una request sin sesión también se registra, con el principal vacío" do
    reset!
    get branch_path

    expect(response).to have_http_status(:unauthorized)
    expect(request_line).to include("status" => 401, "principal_id" => nil, "organization_id" => nil)
  end

  it "registra la IP del cliente como remote_ip" do
    get branch_path, headers: { "REMOTE_ADDR" => "203.0.113.9" }

    expect(request_line["remote_ip"]).to eq("203.0.113.9")
  end

  it "request_id y remote_ip salen de Current (los mismos que anota la auditoría), con la IP ya saneada por el filtro de proxies" do
    reset!
    post "/api/v1/auth/login", params: { email: "no@ceiba.test", password: "x" }, as: :json,
      headers: { "REMOTE_ADDR" => "198.51.100.7", "HTTP_FORWARDED" => "for=6.6.6.6", "HTTP_X_REAL_IP" => "6.6.6.6", "HTTP_USER_AGENT" => "curl/8" }

    audit = Audit::AuthEvent.order(:id).last
    expect(request_line).to include("remote_ip" => "198.51.100.7", "request_id" => response.headers["X-Request-Id"])
    expect(audit).to have_attributes(ip: IPAddr.new("198.51.100.7"), request_id: response.headers["X-Request-Id"])
  end

  it "las sondas /api/health y /api/ready no generan línea (ruido cada pocos segundos)" do
    get "/api/health"

    expect(request_line).to be_nil
  end
end
