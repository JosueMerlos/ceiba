module Database
  # Helpers de migración de las convenciones de BD (docs/architecture/09-data-conventions.md). Se incluyen
  # en el adaptador de PostgreSQL, así que están disponibles en cualquier migración de cualquier pack.
  module SchemaStatements
    # create_tenant_table :branches do |t|
    #   t.tenant_reference :company
    #   t.string :name, null: false
    #   t.timestamps
    # end
    #
    # Crea la tabla con id uuid (uuidv7()), organization_id NOT NULL con FK a organizations, UNIQUE
    # (organization_id, id) para que otras tablas la referencien con FK compuesta y la política RLS
    # `tenant_isolation` (RLS queda DESHABILITADO hasta enable_tenant_rls, M4.03). Acepta las opciones de
    # create_table salvo `id:`. El UNIQUE (organization_id, id) hace también de índice por organización.
    def create_tenant_table(table_name, **options, &block)
      table = table_name.to_s
      raise ArgumentError, "organizations es la raíz del tenant: se crea con create_table, no con create_tenant_table" if table == "organizations"
      raise ArgumentError, "create_tenant_table siempre usa id uuid con uuidv7(); no acepta id: #{options[:id].inspect}" if options.key?(:id) && options[:id] != :uuid

      create_table(table, **options, id: :uuid) do |t|
        t.tenant_table = true
        t.uuid :organization_id, null: false
        block&.call(t)
        raise ArgumentError, "organization_id lo agrega create_tenant_table: no lo declares en #{table}" if t.columns.count { |c| c.name == "organization_id" } > 1

        t.foreign_key :organizations, column: :organization_id, name: "fk_#{table}_organization"
        t.unique_constraint %i[organization_id id], name: "uq_#{table}_organization_id_id"
      end
      create_tenant_policy(table)
    end

    # Activa Row Level Security (M4.03). `force: true` la aplica también al dueño de la tabla (útil en pruebas;
    # en producción la app conecta como app_user, que no es dueño). Solo para tablas de create_tenant_table.
    def enable_tenant_rls(table_name, force: false)
      assert_tenant_table!(table_name)
      execute "ALTER TABLE #{quote_table_name(table_name)} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{quote_table_name(table_name)} FORCE ROW LEVEL SECURITY" if force
    end

    def disable_tenant_rls(table_name)
      assert_tenant_table!(table_name)
      execute "ALTER TABLE #{quote_table_name(table_name)} NO FORCE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{quote_table_name(table_name)} DISABLE ROW LEVEL SECURITY"
    end

    private

    # NULLIF: tras un `SET LOCAL app.organization_id` previo, al terminar la transacción el setting queda como
    # cadena vacía (no NULL) y ''::uuid fallaría; con NULLIF una conexión sin contexto simplemente no ve filas.
    TENANT_PREDICATE = "organization_id = NULLIF(current_setting('app.organization_id', true), '')::uuid".freeze

    def create_tenant_policy(table)
      execute <<~SQL.squish
        CREATE POLICY #{::Database::TenantTables::POLICY_NAME} ON #{quote_table_name(table)}
        USING (#{TENANT_PREDICATE}) WITH CHECK (#{TENANT_PREDICATE})
      SQL
    end

    def assert_tenant_table!(table_name)
      return if ::Database::TenantTables.tenant?(table_name, self)

      raise ArgumentError, "#{table_name} no es una tabla tenant (créala con create_tenant_table)"
    end
  end
end
