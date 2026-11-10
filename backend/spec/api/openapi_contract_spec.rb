require "rails_helper"

# The versioned contract (openapi/v1.yaml) exists, is well formed and documents the WHOLE /api/v1 surface: CI fails if an
# endpoint is undocumented. That the file is UP TO DATE with the specs is checked by infra/scripts/check-api-contract.sh
# (regenerates and compares).
RSpec.describe "Contrato OpenAPI (openapi/v1.yaml)" do
  let(:path) { Rails.root.join("openapi/v1.yaml") }
  let(:document) { YAML.safe_load_file(path) }

  def sorted?(node)
    case node
    when Hash then node.keys == node.keys.sort && node.values.all? { |value| sorted?(value) }
    when Array then node.all? { |value| sorted?(value) }
    else true
    end
  end

  it "existe y es OpenAPI 3.0" do
    expect(path).to exist
    expect(document).to include("openapi" => "3.0.3", "info" => a_hash_including("title" => "Ceiba API", "version" => "v1"))
  end

  it "define los componentes reutilizables Problem y ValidationProblem" do
    expect(document.dig("components", "schemas").keys).to include("Problem", "ValidationProblem", "FieldError", "PageInfo", "Organization")
  end

  it "los errores de cada operación referencian Problem por $ref (no lo repiten)" do
    not_found = document.dig("paths", "/api/v1/organizations/{id}", "get", "responses", "404")

    expect(not_found.dig("content", "application/problem+json", "schema")).to eq("$ref" => "#/components/schemas/Problem")
  end

  it "tiene las claves ordenadas (generación determinista)" do
    expect(sorted?(document)).to be(true)
  end

  it "documenta cada ruta /api/v1 de la aplicación" do
    documented = document.fetch("paths").flat_map { |template, item| item.keys.map { |verb| "#{verb.upcase} #{template}" } }
    routes = Rails.application.routes.routes
      .select { |route| route.path.spec.to_s.start_with?("/api/v1/") }
      .map { |route| "#{route.verb} #{route.path.spec.to_s.delete_suffix('(.:format)').gsub(/:(\w+)/, '{\1}')}" }

    expect(routes).not_to be_empty
    expect(routes - documented).to be_empty, "rutas sin documentar en openapi/v1.yaml: #{(routes - documented).join(', ')}"
  end
end
