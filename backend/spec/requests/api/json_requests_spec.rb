require "rails_helper"

# Toda mutación de la API con cuerpo debe ser JSON (415 en otro caso, problem+json). Evita que un formulario HTML
# cross-site (application/x-www-form-urlencoded, multipart/form-data, text/plain) llegue a un controlador de la API.
RSpec.describe "La API solo acepta cuerpos JSON en las mutaciones" do
  include_context "con endpoints de prueba de la API"

  def expect_unsupported
    expect(response).to have_http_status(:unsupported_media_type)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.parsed_body).to include("status" => 415, "code" => "request.unsupported_media_type")
  end

  it "el login con application/x-www-form-urlencoded responde 415 y no crea la sesión", :aggregate_failures do
    user = create(:user)

    expect do
      post "/api/v1/auth/login", params: "email=#{user.email}&password=#{AuthenticationHelpers::DEFAULT_PASSWORD}", headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    end.not_to change(Identity::Session, :count)

    expect_unsupported
  end

  it "una mutación con text/plain responde 415" do
    post "/api/v1/probes/create", params: "name=x", headers: { "CONTENT_TYPE" => "text/plain" }

    expect_unsupported
  end

  it "una mutación con parámetros de formulario (urlencoded por omisión) responde 415" do
    post "/api/v1/probes/create", params: { name: "x" }

    expect_unsupported
  end

  it "responde 415 antes de autenticar (también sin sesión, en una ruta protegida)" do
    delete "/api/v1/auth/logout", params: "x=1", headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    expect_unsupported
  end

  it "acepta application/json con charset" do
    post "/api/v1/probes/create", params: { name: "x" }.to_json, headers: { "CONTENT_TYPE" => "application/json; charset=utf-8" }

    expect(response).to have_http_status(:created)
  end

  it "acepta una mutación SIN cuerpo (DELETE de logout, POST de acción)" do
    post "/api/v1/probes/create"

    expect(response).to have_http_status(:created)
  end

  it "no afecta a las lecturas" do
    get "/api/v1/probes/ok", headers: { "CONTENT_TYPE" => "text/plain" }

    expect(response).to have_http_status(:ok)
  end

  describe "parámetros en la query string de una mutación" do
    def expect_query_rejected
      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("status" => 400, "code" => "request.query_not_allowed")
    end

    it "el login con las credenciales en la query y cuerpo vacío responde 400 y NO abre sesión", :aggregate_failures do
      user = create(:user)

      expect do
        post "/api/v1/auth/login?#{{ email: user.email, password: AuthenticationHelpers::DEFAULT_PASSWORD }.to_query}"
      end.not_to change(Identity::Session, :count)

      expect_query_rejected
    end

    it "tampoco con un cuerpo JSON válido además de la query" do
      post "/api/v1/probes/create?name=x", params: { name: "y" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect_query_rejected
    end

    it "una mutación sin cuerpo con query (DELETE) responde 400" do
      delete "/api/v1/auth/logout?foo=1"

      expect_query_rejected
    end

    it "las lecturas con query siguen funcionando" do
      get "/api/v1/probes/ok?foo=1"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "fugas en el log" do
    let(:log) { StringIO.new }
    let(:secret) { "ceiba-demo-2026-secreta" }

    around do |example|
      logger = ActiveSupport::Logger.new(log)
      Rails.logger.broadcast_to(logger)
      example.run
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end

    it "un cuerpo JSON SIN Content-Type (Rails lo parsearía como formulario) no deja la contraseña en el log", :aggregate_failures do
      user = create(:user)

      post "/api/v1/auth/login", params: { email: user.email, password: secret }.to_json

      expect(response).to have_http_status(:unsupported_media_type)
      expect(log.string).not_to include(secret)
    end

    it "credenciales en la query string no quedan en el log" do
      post "/api/v1/auth/login?email=ana@ceiba.test&password=#{secret}"

      expect(log.string).not_to include(secret)
    end

    it "un formulario urlencoded con la contraseña no queda en el log" do
      post "/api/v1/auth/login", params: "email=ana@ceiba.test&password=#{secret}", headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

      expect(log.string).not_to include(secret)
    end

    it "el login JSON correcto sigue filtrando la contraseña" do
      user = create(:user, password: secret)

      post "/api/v1/auth/login", params: { email: user.email, password: secret }, as: :json

      expect(response).to have_http_status(:ok)
      expect(log.string).not_to include(secret)
    end
  end
end
