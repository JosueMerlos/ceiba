require "rails_helper"
require "openapi/normalizer"

# Non-deterministic generation causes false drifts: the YAML comes out with sorted keys, regardless of the order rswag
# accumulated the specs in.
RSpec.describe Openapi::Normalizer do
  it "ordena las claves de los hashes en todos los niveles" do
    document = { "paths" => { "/b" => { "get" => 1 }, "/a" => { "post" => 1, "get" => 2 } }, "info" => {} }

    result = described_class.call(document)

    expect(result.keys).to eq(%w[info paths])
    expect(result["paths"].keys).to eq(%w[/a /b])
    expect(result.dig("paths", "/a").keys).to eq(%w[get post])
  end

  it "conserva el orden de los arrays (parameters, required, enum son significativos)" do
    result = described_class.call({ "required" => %w[b a], "oneOf" => [ { "z" => 1, "a" => 2 }, { "b" => 1 } ] })

    expect(result["required"]).to eq(%w[b a])
    expect(result["oneOf"].first.keys).to eq(%w[a z])
  end

  it "convierte los valores simbólicos en texto (el YAML no debe llevar !ruby/symbol)" do
    expect(described_class.call({ type: :object, required: %i[id name] })).to eq({ "required" => %w[id name], "type" => "object" })
  end

  it "convierte claves simbólicas a texto y es idempotente" do
    once = described_class.call({ b: { d: 1, c: 2 }, a: [ { y: 1, x: 2 } ] })

    expect(once).to eq({ "a" => [ { "x" => 2, "y" => 1 } ], "b" => { "c" => 2, "d" => 1 } })
    expect(described_class.call(once)).to eq(once)
  end
end
