# frozen_string_literal: true

require "rails/generators"

# bin/rails g pack <capa>/<nombre>
#
# Crea un pack con la estructura de docs/architecture/02-modular-monolith.md: package.yml con
# la capa y los checkers activos, directorios de app/, locales y un spec base (más un manifest.rb
# placeholder en modules/). Nace cumpliendo las reglas que verifica packwerk en CI.
class PackGenerator < Rails::Generators::Base
  LAYERS = %w[platform modules].freeze
  NAME_FORMAT = /\A[a-z][a-z0-9]*(_[a-z0-9]+)*\z/
  # Nombres que chocarían con constantes o palabras reservadas como namespace.
  RESERVED_NAMES = %w[
    class module object kernel rails ruby active_record active_support action_controller
    application api concerns app lib spec test config db
  ].freeze
  APP_DIRECTORIES = %w[public models services policies serializers jobs subscribers].freeze

  source_root File.expand_path("templates", __dir__)
  desc "Crea un pack en packs/<capa>/<nombre> (capas: #{LAYERS.join(', ')})"
  argument :path, type: :string, banner: "<capa>/<nombre>"

  def validate_path
    layer_name, pack_name, *rest = path.to_s.split("/", -1)
    raise Thor::Error, "Formato inválido: usa <capa>/<nombre> (ej. modules/billing)" if pack_name.nil? || rest.any?

    @layer = layer_name
    @pack_name = pack_name
    validate_layer!
    validate_name!
    validate_availability!
  end

  def create_package_files
    template "package.yml.tt", pack_path("package.yml")
    template "manifest.rb.tt", pack_path("manifest.rb") if modules_layer?
    template "es-NI.yml.tt", pack_path("config/locales/es-NI.yml")
    template "package_spec.rb.tt", pack_path("spec/package_spec.rb")
  end

  def create_directories
    APP_DIRECTORIES.each { |directory| keep pack_path("app/#{directory}/#{@pack_name}") }
    keep pack_path("app/controllers/api/v1/#{@pack_name}")
    keep pack_path("db/migrate")
  end

  def print_next_steps
    say <<~TEXT

      Pack #{pack_path} creado. Siguientes pasos:
        bundle exec packwerk validate && bundle exec packwerk check
        declara en package.yml las dependencias que uses (platform/... desde modules/...)
    TEXT
  end

  private

  attr_reader :layer, :pack_name

  def modules_layer?
    layer == "modules"
  end

  def namespace
    pack_name.split("_").map(&:capitalize).join
  end

  def pack_path(relative = nil)
    File.join(*[ "packs", layer, pack_name, relative ].compact)
  end

  def keep(directory)
    create_file File.join(directory, ".keep"), ""
  end

  def validate_layer!
    return if LAYERS.include?(layer)

    raise Thor::Error, "Capa inválida #{layer.inspect}: las capas son #{LAYERS.join(' y ')}"
  end

  def validate_name!
    raise Thor::Error, "Nombre inválido #{pack_name.inspect}: usa snake_case (a-z, 0-9 y _; empieza por letra)" unless NAME_FORMAT.match?(pack_name)
    raise Thor::Error, "Nombre reservado #{pack_name.inspect}: elige otro" if RESERVED_NAMES.include?(pack_name)
    return unless Object.const_defined?(namespace)

    raise Thor::Error, "El namespace #{namespace} choca con una constante existente (#{pack_name.inspect}): elige otro nombre"
  end

  def validate_availability!
    existing = LAYERS.find { |candidate| File.directory?(File.join(destination_root, "packs", candidate, pack_name)) }
    return unless existing

    if existing == layer
      raise Thor::Error, "El pack #{pack_path} ya existe"
    else
      raise Thor::Error, "El namespace #{namespace} ya lo usa packs/#{existing}/#{pack_name}: los nombres son únicos entre capas"
    end
  end
end
