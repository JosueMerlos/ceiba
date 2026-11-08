require "rails_helper"
require "ci/pack_contract"
require "tmpdir"

RSpec.describe PackContract do
  subject(:violations) { described_class.new(root, visible_to: allowlist).violations }

  let(:root) { Pathname(Dir.mktmpdir("ceiba-pack-contract")) }
  let(:allowlist) { {} }
  let(:valid_module) do
    { "layer" => "modules", "enforce_dependencies" => true, "enforce_privacy" => true, "enforce_layers" => true,
      "enforce_visibility" => true, "visible_to" => [] }
  end
  let(:valid_platform) { valid_module.except("enforce_visibility", "visible_to").merge("layer" => "platform") }

  after { FileUtils.remove_entry(root) }

  def write_pack(path, config)
    dir = root.join("packs", path)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("package.yml"), config.to_yaml) if config
  end

  context "con packs que cumplen el contrato" do
    before do
      write_pack("modules/foo", valid_module)
      write_pack("platform/bar", valid_platform)
    end

    it { is_expected.to be_empty }
  end

  context "sin packs" do
    it { is_expected.to be_empty }
  end

  context "con un directorio de pack sin package.yml" do
    before { write_pack("modules/foo", nil) }

    it { is_expected.to contain_exactly(a_string_matching(%r{packs/modules/foo.*sin package\.yml})) }
  end

  context "con un pack fuera de las capas" do
    before { write_pack("core/foo", valid_module) }

    it { is_expected.to contain_exactly(a_string_matching(%r{packs/core/foo.*capa})) }
  end

  context "con la capa de package.yml distinta de su carpeta" do
    before { write_pack("modules/foo", valid_module.merge("layer" => "platform")) }

    it { is_expected.to contain_exactly(a_string_matching(/layer.*platform.*modules/)) }
  end

  %w[enforce_dependencies enforce_privacy enforce_layers].each do |key|
    context "con #{key} en false" do
      before { write_pack("modules/foo", valid_module.merge(key => false)) }

      it { is_expected.to contain_exactly(a_string_matching(/#{key}/)) }
    end

    context "con #{key} en strict (solo se acepta true)" do
      before { write_pack("platform/foo", valid_platform.merge(key => "strict")) }

      it { is_expected.to contain_exactly(a_string_matching(/#{key}/)) }
    end
  end

  context "con un módulo sin enforce_visibility" do
    before { write_pack("modules/foo", valid_module.except("enforce_visibility")) }

    it { is_expected.to contain_exactly(a_string_matching(/enforce_visibility/)) }
  end

  context "con un módulo con enforce_visibility en false" do
    before { write_pack("modules/foo", valid_module.merge("enforce_visibility" => false)) }

    it { is_expected.to contain_exactly(a_string_matching(/enforce_visibility/)) }
  end

  context "con un módulo visible a otro pack fuera de la lista permitida" do
    before { write_pack("modules/foo", valid_module.merge("visible_to" => [ "packs/modules/other" ])) }

    it { is_expected.to contain_exactly(a_string_matching(%r{visible_to.*packs/modules/other})) }
  end

  context "con un módulo sin visible_to" do
    before { write_pack("modules/foo", valid_module.except("visible_to")) }

    it { is_expected.to contain_exactly(a_string_matching(/visible_to/)) }
  end

  context "con un módulo visible a un pack de la lista permitida" do
    let(:allowlist) { { "packs/modules/foo" => [ "." ] } }

    before { write_pack("modules/foo", valid_module.merge("visible_to" => [ "." ])) }

    it { is_expected.to be_empty }
  end

  context "con un package.yml que no es un mapa" do
    before do
      FileUtils.mkdir_p(root.join("packs/modules/foo"))
      File.write(root.join("packs/modules/foo/package.yml"), "- uno\n")
    end

    it { is_expected.to contain_exactly(a_string_matching(/no es un mapa/)) }
  end
end
