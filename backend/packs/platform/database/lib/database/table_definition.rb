module Database
  # `t.tenant_reference` inside `create_tenant_table`: a reference to another tenant table that the database
  # engine forces to belong to the SAME tenant (composite FK).
  module TableDefinition
    ON_DELETE_OPTIONS = %i[restrict cascade].freeze
    MAX_IDENTIFIER_LENGTH = 63 # PostgreSQL silently truncates longer identifiers

    def self.validate_on_delete!(value)
      return value.to_sym if ON_DELETE_OPTIONS.include?(value&.to_sym)

      detail = value&.to_sym == :nullify ? "anularía organization_id (NOT NULL y parte de la FK compuesta). " : ""
      raise ArgumentError, "on_delete: #{value.inspect} no es válido para tablas tenant. #{detail}Usa :restrict (por defecto) o :cascade."
    end

    def self.constraint_name!(name)
      return name if name.length <= MAX_IDENTIFIER_LENGTH

      raise ArgumentError, "El nombre de restricción #{name.inspect} tiene #{name.length} caracteres y supera #{MAX_IDENTIFIER_LENGTH} caracteres " \
                           "(PostgreSQL lo truncaría y podría colisionar): usa un nombre de tabla/referencia más corto."
    end

    # Set by create_tenant_table; outside it there is no organization_id to build the composite FK on.
    attr_accessor :tenant_table

    # t.tenant_reference :company
    #   company_id uuid NOT NULL
    #   FOREIGN KEY (organization_id, company_id) REFERENCES companies (organization_id, id)
    #   INDEX (organization_id, company_id)
    #
    # :nullify is rejected for on_delete because it would null organization_id.
    def tenant_reference(reference, null: false, to_table: nil, index: true, foreign_key: true, on_delete: :restrict)
      raise ArgumentError, "tenant_reference solo puede usarse dentro de create_tenant_table" unless tenant_table

      on_delete = TableDefinition.validate_on_delete!(on_delete)
      column = "#{reference}_id"
      uuid column, null: null
      if foreign_key
        self.foreign_key(to_table || reference.to_s.pluralize,
                         column: [ "organization_id", column ], primary_key: [ "organization_id", "id" ],
                         name: TableDefinition.constraint_name!("fk_#{name}_#{reference}"), on_delete: on_delete)
      end
      self.index([ "organization_id", column ]) if index
    end
  end
end
