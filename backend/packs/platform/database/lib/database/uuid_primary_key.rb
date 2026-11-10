module Database
  # Every `uuid` PK defaults to PostgreSQL 18's `uuidv7()` instead of the `gen_random_uuid()` (UUIDv4) Rails uses,
  # so `create_table :foos, id: :uuid` (what `rails g model` emits) is correct without extra work.
  # An explicit default is respected.
  module UuidPrimaryKey
    DEFAULT = "uuidv7()".freeze

    def primary_key(name, type = :primary_key, **options)
      options[:default] = DEFAULT if type == :uuid && !options.key?(:default)
      super
    end
  end
end
