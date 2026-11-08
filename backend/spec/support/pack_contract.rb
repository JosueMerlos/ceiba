# Contrato que cumple todo pack (docs/architecture/02-modular-monolith.md). Lo usa el spec base que
# genera `bin/rails g pack`; si el contrato cambia, cambia aquí y rige para todos los packs.
RSpec.shared_examples "un pack del monolito modular" do |layer:, pack_root:|
  let(:package) { YAML.safe_load_file(Rails.root.join(pack_root, "package.yml")) }

  it "declara su capa" do
    expect(package["layer"]).to eq(layer)
  end

  it "exige dependencias, privacidad y capas" do
    expect(package).to include("enforce_dependencies" => true, "enforce_privacy" => true, "enforce_layers" => true)
  end

  it "es invisible para los demás packs si es un módulo (los módulos no se usan entre sí)" do
    expectation = layer == "modules" ? { "enforce_visibility" => true, "visible_to" => [] } : {}

    expect(package.slice("enforce_visibility", "visible_to")).to eq(expectation)
  end

  it "vive en la carpeta de su capa" do
    expect(pack_root).to start_with("packs/#{layer}/")
  end

  it "tiene el manifiesto si es un módulo" do
    expect(Rails.root.join(pack_root, "manifest.rb").exist?).to eq(layer == "modules")
  end
end
