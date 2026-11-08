module Database
  # Toda PK `uuid` usa el default `uuidv7()` de PostgreSQL 18 (ADR-0006) en lugar del `gen_random_uuid()`
  # (UUIDv4) que Rails pone por defecto: así `create_table :foos, id: :uuid` (lo que genera
  # `rails g model` con primary_key_type: :uuid) es correcto sin recordar nada. Un default explícito se respeta.
  module UuidPrimaryKey
    DEFAULT = "uuidv7()".freeze

    def primary_key(name, type = :primary_key, **options)
      options[:default] = DEFAULT if type == :uuid && !options.key?(:default)
      super
    end
  end
end
