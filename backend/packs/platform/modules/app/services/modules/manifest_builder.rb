module Modules
  # El DSL de `Modules.define` (docs/architecture/05-module-system.md). Recoge lo declarado SIN validar (eso lo hace
  # ManifestValidator) y entrega un Manifest inmutable. Solo existen los campos de 05: cualquier otro es un error.
  class ManifestBuilder
    FIELDS = %i[
      name version requires platform permissions role_grants api_scopes settings_schema settings_levels publishes subscribes
      navigation on_enable on_disable
    ].freeze

    # Lo declarado, tal cual (cadenas/hashes crudos). Lo lee ManifestValidator.
    Declared = Data.define(
      :key, :root, :name, :version, :requires, :platform, :permissions, :role_grants, :api_scopes, :settings_source,
      :settings_levels, :publishes, :subscribes, :navigation, :on_enable, :on_disable
    )

    def self.build(key, root:, &block) = new(key, root:).tap { |builder| builder.instance_eval(&block) if block }.declared

    def initialize(key, root:)
      @key = key
      @root = root
      @requires = []
      @platform = []
      @permissions = []
      @role_grants = {}
      @api_scopes = {}
      @settings_levels = %w[company]
      @publishes = []
      @subscribes = {}
      @navigation = []
    end

    def name(value) = @name = value
    def version(value) = @version = value
    def requires(keys) = @requires = Array(keys)
    def platform(capabilities) = @platform = Array(capabilities)
    def api_scopes(scopes) = @api_scopes = scopes
    # Ruta (relativa al pack) de un archivo JSON Schema, o el esquema mismo como Hash.
    def settings_schema(source) = @settings_source = source
    def settings_levels(levels) = @settings_levels = Array(levels)
    def publishes(events) = @publishes = Array(events)
    # `subscribes {}` (como en la doc) llega como un bloque vacío: se ignora y queda sin suscripciones.
    def subscribes(events = {}) = @subscribes = events
    def navigation(items) = @navigation = Array(items)
    def on_enable(constant_name) = @on_enable = constant_name
    def on_disable(constant_name) = @on_disable = constant_name

    def permissions(&block)
      return @permissions unless block

      @permissions = PermissionsBlock.new.tap { |collector| collector.instance_eval(&block) }.declared
    end

    def role_grants(&block)
      return @role_grants unless block

      @role_grants = GrantsBlock.new.tap { |collector| collector.instance_eval(&block) }.declared
    end

    def declared
      Declared.new(
        key: @key, root: @root, name: @name, version: @version, requires: @requires, platform: @platform,
        permissions: @permissions, role_grants: @role_grants, api_scopes: @api_scopes, settings_source: @settings_source,
        settings_levels: @settings_levels, publishes: @publishes, subscribes: @subscribes, navigation: @navigation,
        on_enable: @on_enable, on_disable: @on_disable
      )
    end

    def method_missing(name, *)
      raise InvalidManifest.new(@key, [ "campo desconocido: #{name} (los campos del manifiesto son #{FIELDS.join(', ')})" ])
    end

    def respond_to_missing?(*) = false

    # `permissions do permission "x.y.z", description: "..." end`
    class PermissionsBlock
      def initialize = @declared = []
      attr_reader :declared

      def permission(key, description: nil) = @declared << { key: key.to_s, description: description.to_s.strip }
    end

    # `role_grants do grant :receptionist, %w[...]; grant :company_manager, all: true end`
    class GrantsBlock
      def initialize = @declared = {}
      attr_reader :declared

      def grant(role, keys = [], all: false) = @declared[role.to_s] = all ? :all : Array(keys).map(&:to_s)
    end
  end
end
