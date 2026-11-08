# frozen_string_literal: true

require "pathname"
require "yaml"

# Contrato que debe cumplir TODO pack de packs/<capa>/<nombre> (docs/architecture/02-modular-monolith.md).
# Lo aplica spec/packs/contract_spec.rb sobre los packs reales: así el aislamiento entre módulos no
# depende de que cada pack conserve su propio spec ni de que el package.yml no se edite a mano.
#
# `visible_to` es la lista explícita y mínima de packs que pueden usar a un módulo, por pack
# (hoy ninguno: ver "Cómo se cablea M0.09" en 02). Todo lo que no esté ahí es una violación.
class PackContract
  LAYERS = %w[platform modules].freeze
  ENFORCEMENTS = %w[enforce_dependencies enforce_privacy enforce_layers].freeze
  ALLOWED_VISIBLE_TO = {}.freeze

  def initialize(root, visible_to: ALLOWED_VISIBLE_TO)
    @root = Pathname(root)
    @visible_to = visible_to
  end

  def violations
    pack_directories.flat_map { |directory| pack_violations(directory) }
  end

  private

  attr_reader :root, :visible_to

  def pack_directories
    root.glob("packs/*/*").select(&:directory?).sort
  end

  def pack_violations(directory)
    name = directory.relative_path_from(root).to_s
    layer = directory.parent.basename.to_s
    return [ "#{name}: la capa #{layer.inspect} no existe (capas: #{LAYERS.join(', ')})" ] unless LAYERS.include?(layer)

    manifest = directory.join("package.yml")
    return [ "#{name}: sin package.yml" ] unless manifest.file?

    config = YAML.safe_load_file(manifest)
    return [ "#{name}: package.yml no es un mapa" ] unless config.is_a?(Hash)

    layer_violations(name, layer, config) + enforcement_violations(name, config) + visibility_violations(name, layer, config)
  end

  def layer_violations(name, layer, config)
    return [] if config["layer"] == layer

    [ "#{name}: layer es #{config['layer'].inspect} y la carpeta dice #{layer.inspect}" ]
  end

  def enforcement_violations(name, config)
    ENFORCEMENTS.reject { |key| config[key] == true }.map { |key| "#{name}: #{key} debe ser true" }
  end

  def visibility_violations(name, layer, config)
    return [] unless layer == "modules"

    problems = []
    problems << "#{name}: enforce_visibility debe ser true" unless config["enforce_visibility"] == true
    allowed = visible_to.fetch(name, [])
    problems << "#{name}: visible_to debe ser #{allowed.inspect} y es #{config['visible_to'].inspect}" unless config["visible_to"] == allowed
    problems
  end
end
