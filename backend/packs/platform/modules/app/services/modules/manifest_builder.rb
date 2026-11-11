module Modules
  # The `Modules.define` DSL. Collects what is declared WITHOUT validating (ManifestValidator does that). Only FIELDS exist;
  # any other is an error.
  class ManifestBuilder
    FIELDS = %i[
      name version requires platform permissions role_grants api_scopes settings_schema settings_levels publishes subscribes
      navigation on_enable on_disable
    ].freeze

    # Raw declared values, read by ManifestValidator.
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
    # Path (relative to the pack) of a JSON Schema file, or the schema itself as a Hash.
    def settings_schema(source) = @settings_source = source
    def settings_levels(levels) = @settings_levels = Array(levels)
    def publishes(events) = @publishes = Array(events)
    # `subscribes {}` arrives as an empty block: ignored, leaving no subscriptions.
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

    class PermissionsBlock
      def initialize = @declared = []
      attr_reader :declared

      def permission(key, description: nil, from_descendants: false)
        @declared << { key: key.to_s, description: description.to_s.strip, from_descendants: }
      end
    end

    class GrantsBlock
      def initialize = @declared = {}
      attr_reader :declared

      def grant(role, keys = [], all: false) = @declared[role.to_s] = all ? :all : Array(keys).map(&:to_s)
    end
  end
end
