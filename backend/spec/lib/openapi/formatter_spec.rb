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
end
