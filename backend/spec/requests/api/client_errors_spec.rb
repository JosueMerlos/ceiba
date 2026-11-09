require "rails_helper"

# Revisión de M0.06: los errores del CLIENTE que Rails ya sabe clasificar (método HTTP desconocido, tipo de contenido
# inválido, formato no soportado...) no son bugs: no se responden 500 ni se reportan como tales.
RSpec.describe "Errores de cliente de la API y rutas fuera de /api" do
  include_context "con endpoints de prueba de la API"

  def expect_problem(status:, code:)
    expect(response).to have_http_status(status)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.parsed_body).to include("code" => code)
  end

  before { allow(Api::ErrorReporter).to receive(:call) }

  it "una ruta fuera de /api sigue respondiendo 404 (no status 0)" do
    get "/nope", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).not_to eq("application/problem+json")
  end

  it "un método HTTP desconocido responde 405 problem+json y no se reporta" do
    process :foo, "/api/v1/probes/ok"

    expect_problem(status: :method_not_allowed, code: "request.method_not_allowed")
    expect(Api::ErrorReporter).not_to have_received(:call)
  end

  it "un Content-Type malformado responde 406 problem+json y no se reporta" do
    post "/api/v1/probes/create", headers: { "CONTENT_TYPE" => "malformado" }, params: "x"

    expect_problem(status: :not_acceptable, code: "request.not_acceptable")
    expect(Api::ErrorReporter).not_to have_received(:call)
  end

  it "un formato no soportado (UnknownFormat) responde 406 problem+json" do
    get "/api/v1/probes/unknown_format"

    expect_problem(status: :not_acceptable, code: "request.unknown_format")
  end

  it "NotImplemented responde 501 problem+json sin reportarse como bug" do
    get "/api/v1/probes/not_implemented"

    expect_problem(status: :not_implemented, code: "request.not_implemented")
    expect(Api::ErrorReporter).not_to have_received(:call)
  end

  it "una excepción de cliente que Rails clasifica pero no está registrada usa el status de Rails con un code genérico" do
    get "/api/v1/probes/client_error_unregistered"

    expect_problem(status: :unprocessable_content, code: "http.422")
    expect(Api::ErrorReporter).not_to have_received(:call)
  end

  it "un 500 real sí se reporta" do
    get "/api/v1/probes/boom"

    expect(Api::ErrorReporter).to have_received(:call)
  end
end
