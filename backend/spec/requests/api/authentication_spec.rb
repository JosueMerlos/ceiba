require "rails_helper"

# DENY BY DEFAULT: every route requires a session except an explicit, commented and MINIMAL allowlist. This spec walks
# ALL the router's routes (not a hand-kept controller list): a new route without `skip_authentication!` answers 401 and
# passes; one left open by mistake breaks here.
RSpec.describe "Autenticación obligatoria por defecto (deny by default)" do
  # Routes that do NOT require a session, with the reason. Adding one here is a security decision: reviewed in the PR.
  let(:public_routes) do
    {
      "GET /api/health" => "sonda de vida del proxy/Docker: infraestructura, no devuelve datos",
      "GET /api/ready" => "sonda de disponibilidad (BD, Redis): infraestructura",
      "POST /api/v1/auth/login" => "es la puerta de entrada: aún no hay sesión; protegido por Origin y, en M0.13, por rate limit",
      # Rswag mounts TWO engines at /api/docs (UI and contract) and their subroutes (/api/docs/v1.yaml, assets) do not
      # appear in the app's route table, so this spec does not walk them: public by design and only present where
      # Api::Docs.enabled? (development, test, staging); in production the route does not exist.
      "GET /api/docs" => "Swagger UI y contrato: solo existen en desarrollo, test y staging (Api::Docs.enabled?)"
    }
  end

  let(:routes) do
    Rails.application.routes.routes.map do |route|
      { verb: route.verb.presence || "GET", path: route.path.spec.to_s.sub("(.:format)", ""), engine: route.verb.blank? }
    end
  end

  def concrete(path) = path.gsub(%r{/[:*]\w+}, "/0198f0a0-0000-7000-8000-000000000000")

  def label(route) = "#{route[:verb]} #{route[:path]}"

  it "todas las rutas, salvo la allowlist, responden 401 sin sesión" do
    protected_routes = routes.reject { |route| public_routes.key?(label(route)) }
    expect(protected_routes).not_to be_empty

    offenders = protected_routes.filter_map do |route|
      process(route[:verb].downcase, concrete(route[:path]))
      "#{label(route)} -> #{response.status}" unless response.status == 401
    end

    expect(offenders).to be_empty
  end

  it "las rutas de ActiveStorage no existen mientras ningún hito las use (serían subidas sin sesión)" do
    expect(routes.map { |route| route[:path] }).not_to include(a_string_starting_with("/rails/active_storage"))
  end

  it "la allowlist no tiene entradas obsoletas: cada una corresponde a una ruta real" do
    existing = routes.map { |route| label(route) }

    expect(public_routes.keys - existing).to be_empty
  end

  it "cada ruta pública responde sin sesión (no 401)" do
    public_routes.each_key do |entry|
      verb, path = entry.split(" ", 2)
      next if path == "/api/docs" # engine-mounted route: docs_spec covers it

      process(verb.downcase, path, params: (verb == "POST" ? {} : nil), as: :json)
      expect(response.status).not_to eq(401), "#{entry} respondió 401"
    end
  end

  context "con una ruta nueva que hereda de Api::BaseController y NO declara skip_authentication!" do
    include_context "con endpoints de prueba de la API"

    it "responde 401 sin sesión, con problem+json" do
      get "/api/v1/probes/guarded"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to include("code" => "auth.unauthenticated")
    end
  end

  it "el endpoint de ejemplo de organizaciones exige sesión" do
    get "/api/v1/organizations/#{create(:organization).id}"

    expect(response).to have_http_status(:unauthorized)
  end
end
