module Database
  # Migration helpers for the DB conventions. Included in the PostgreSQL adapter, so any pack's migration can use them.
  module SchemaStatements
    # create_tenant_table :branches do |t|
    #   t.tenant_reference :company
    #   t.string :name, null: false
    #   t.timestamps
    # end
    #
    # Creates the table with a uuidv7() id, organization_id NOT NULL with an FK to organizations, a UNIQUE
    # (organization_id, id) so other tables can reference it with a composite FK (it also serves as the per-organization
    # index), and the `tenant_isolation` RLS policy (RLS stays DISABLED until enable_tenant_rls). Accepts create_table's
    # options except `id:`.
    #
    # `on_delete:` governs the FK to organizations; :nullify is rejected (organization_id is NOT NULL). Deleting an
    # organization with data must be an explicit operation, not a side effect, hence the :restrict default.
    def create_tenant_table(table_name, on_delete: :restrict, **options, &block)
      table = table_name.to_s
      on_delete = ::Database::TableDefinition.validate_on_delete!(on_delete)
      fk_name = ::Database::TableDefinition.constraint_name!("fk_#{table}_organization")
      unique_name = ::Database::TableDefinition.constraint_name!("uq_#{table}_organization_id_id")
      raise ArgumentError, "organizations es la raíz del tenant: se crea con create_table, no con create_tenant_table" if table == "organizations"
      raise ArgumentError, "create_tenant_table siempre usa id uuid con uuidv7(); no acepta id: #{options[:id].inspect}" if options.key?(:id) && options[:id] != :uuid

      create_table(table, **options, id: :uuid) do |t|
        t.tenant_table = true
        t.uuid :organization_id, null: false
        block&.call(t)
        raise ArgumentError, "organization_id lo agrega create_tenant_table: no lo declares en #{table}" if t.columns.count { |c| c.name == "organization_id" } > 1

        t.foreign_key :organizations, column: :organization_id, name: fk_name, on_delete: on_delete
        t.unique_constraint %i[organization_id id], name: unique_name
      end
      create_tenant_policy(table)
    end

    # Enables Row Level Security. `force: true` applies it to the table owner too (useful in tests; in production
    # the app connects as app_user, which is not the owner). Only for tables made by create_tenant_table.
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

    # NULLIF: after an earlier `SET LOCAL app.organization_id`, the setting is left as an empty string (not NULL) once
    # the transaction ends and ''::uuid would fail; with NULLIF a connection without context simply sees no rows.
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
