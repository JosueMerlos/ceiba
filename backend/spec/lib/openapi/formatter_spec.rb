require "rails_helper"
require "openapi/formatter"

RSpec.describe Openapi::Formatter do
  def render(document)
    formatter = described_class.allocate
    formatter.instance_variable_set(:@config, Rswag::Specs::Configuration.new(RSpec.configuration).tap { |config| allow(config).to receive(:openapi_format).and_return(:yaml) })
    formatter.send(:pretty_generate, document)
  end

  it "produce exactamente el mismo YAML aunque el orden de inserción cambie" do
    one = { openapi: "3.0.3", paths: { "/b" => { get: { x: 1, a: 2 } }, "/a" => {} }, components: { schemas: { B: {}, A: {} } } }
    other = { components: { schemas: { A: {}, B: {} } }, paths: { "/a" => {}, "/b" => { get: { a: 2, x: 1 } } }, openapi: "3.0.3" }

    expect(render(one)).to eq(render(other))
  end

  it "emite las claves ordenadas" do
    yaml = render({ paths: {}, openapi: "3.0.3", info: {} })

    expect(yaml.lines.grep(/\A\w/).map { |line| line[/\A\w+/] }).to eq(%w[info openapi paths])
  end

  describe "tipos de contenido por respuesta" do
    let(:content) do
      { "application/json" => { schema: { type: "object" } }, "application/problem+json" => { schema: { type: "object" } } }
    end
    let(:document) do
      { openapi: "3.0.3", paths: { "/x" => { get: { responses: { "200" => { content: content }, "404" => { content: content }, "204" => { description: "sin cuerpo" } } } } } }
    end
    let(:responses) { YAML.safe_load(render(document)).dig("paths", "/x", "get", "responses") }

    it "deja solo application/json en los éxitos y solo application/problem+json en los errores (rswag lo declara por operación)" do
      expect(responses.dig("200", "content").keys).to eq([ "application/json" ])
      expect(responses.dig("404", "content").keys).to eq([ "application/problem+json" ])
    end

    it "no inventa contenido en respuestas sin cuerpo" do
      expect(responses["204"]).to eq("description" => "sin cuerpo")
    end
  end
end
