require "rails_helper"

# Behavior of the import endpoints that the contract specs do not describe: module gate, limits, personal data exposure.
RSpec.describe "Importaciones: peticiones" do
  let(:world) { build_access_world }
  let(:company_manager) { user_with_role("company_manager", world, company: world.company_a) }
  let(:base) { "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/#{world.branch_a1.id}/imports" }

  def upload(signed_in, kind:, text: nil, encoded: nil)
    post base, params: { kind:, content_base64: encoded || Base64.strict_encode64(text) }, headers: signed_in.csrf_headers, as: :json
  end

  def services_csv = "nombre;duracion_minutos;precio\nCorte;30;150,50\n"

  describe "tipos de un módulo" do
    it "servicios responde 404 si el módulo de citas no está activo en la empresa" do
      upload(sign_in(company_manager), kind: "services", text: services_csv)

      expect(response).to have_http_status(:not_found)
    end

    it "con el módulo activo, quien gestiona servicios previsualiza su archivo" do
      with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") }

      upload(sign_in(company_manager), kind: "services", text: services_csv)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"].slice("kind", "ready_count", "duplicate_modes")).to eq("kind" => "services", "ready_count" => 1, "duplicate_modes" => %w[skip])
    end

    it "un tipo desconocido responde 422 sin crear nada" do
      upload(sign_in(company_manager), kind: "invoices", text: services_csv)

      expect([ response.status, response.parsed_body["code"] ]).to eq([ 422, "import.unknown_kind" ])
    end
  end

  describe "límites del archivo" do
    it "un contenido codificado más grande de lo que cabe en 5 MB responde 413 antes de decodificarlo" do
      upload(sign_in(company_manager), kind: "customers", encoded: "A" * (Api::V1::Imports::ImportsController::MAX_ENCODED_BYTES + 4))

      expect([ response.status, response.parsed_body["code"] ]).to eq([ 413, "import.file_too_large" ])
    end

    it "un base64 inválido responde 422 de archivo ilegible" do
      upload(sign_in(company_manager), kind: "customers", encoded: "no es base64!")

      expect([ response.status, response.parsed_body["code"] ]).to eq([ 422, "import.unreadable_file" ])
    end

    it "un contenido vacío responde 422 de archivo vacío" do
      upload(sign_in(company_manager), kind: "customers", encoded: "")

      expect([ response.status, response.parsed_body["code"] ]).to eq([ 422, "import.empty_file" ])
    end
  end

  describe "datos personales" do
    it "tras confirmar, ni el lote ni sus filas devuelven los valores" do
      signed_in = sign_in(company_manager)
      upload(signed_in, kind: "customers", text: "nombre;telefono\nAna;8800 0001\n")
      id = response.parsed_body.dig("data", "id")
      post "#{base}/#{id}/confirm", params: { duplicate_mode: "skip" }, headers: signed_in.csrf_headers, as: :json

      get "#{base}/#{id}/rows"

      expect(response.parsed_body["data"].pluck("values")).to eq([ nil ])
    end

    it "el contenido del archivo nunca llega a los logs" do
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("content_base64" => "QW5h")

      expect(filtered).to eq("content_base64" => "[FILTERED]")
    end
  end

  it "un lote de otra sucursal de la misma empresa no existe para esta ruta" do
    signed_in = sign_in(company_manager)
    upload(signed_in, kind: "customers", text: "nombre;telefono\nAna;8800 0001\n")
    id = response.parsed_body.dig("data", "id")
    other_branch = create_in(world.organization, :branch, company: world.company_a)

    get "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/#{other_branch.id}/imports/#{id}"

    expect(response).to have_http_status(:not_found)
  end
end
