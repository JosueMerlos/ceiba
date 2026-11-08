module Database
  # `t.tenant_reference` dentro de `create_tenant_table`: una referencia a otra tabla tenant que el motor
  # obliga a ser del MISMO tenant (barrera 2 de docs/architecture/03-multi-tenancy.md).
  module TableDefinition
    # Lo activa create_tenant_table; fuera de él no hay organization_id contra el que componer la FK.
    attr_accessor :tenant_table

    # t.tenant_reference :company
    #   company_id uuid NOT NULL
    #   FOREIGN KEY (organization_id, company_id) REFERENCES companies (organization_id, id)
    #   INDEX (organization_id, company_id)
    #
    # Opciones: null: (false), to_table: (el plural del nombre), index: (true), foreign_key: (true).
    def tenant_reference(reference, null: false, to_table: nil, index: true, foreign_key: true)
      raise ArgumentError, "tenant_reference solo puede usarse dentro de create_tenant_table" unless tenant_table

      column = "#{reference}_id"
      uuid column, null: null
      if foreign_key
        self.foreign_key(to_table || reference.to_s.pluralize,
                         column: [ "organization_id", column ], primary_key: [ "organization_id", "id" ],
                         name: "fk_#{name}_#{reference}")
      end
      self.index([ "organization_id", column ]) if index
    end
  end
end
