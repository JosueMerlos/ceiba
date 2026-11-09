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
end
