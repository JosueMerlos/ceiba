module Database
  # Registry of tenant tables. A table is tenant if `create_tenant_table` gave it the `tenant_isolation` policy.
  # The registry is DERIVED from the PostgreSQL catalog (pg_policies) instead of duplicated in its own table,
  # so it cannot drift, ships inside structure.sql and needs no extra migrations.
  module TenantTables
    POLICY_NAME = "tenant_isolation".freeze

    module_function

    def names(connection = ActiveRecord::Base.connection)
      connection.select_values(<<~SQL)
        SELECT tablename FROM pg_policies
        WHERE schemaname = current_schema() AND policyname = #{connection.quote(POLICY_NAME)}
        ORDER BY tablename
      SQL
    end

    # Tenant tables that already have RLS enabled.
    def rls_enabled(connection = ActiveRecord::Base.connection)
      connection.select_values(<<~SQL)
        SELECT c.relname FROM pg_class c
        JOIN pg_policies p ON p.schemaname = current_schema() AND p.tablename = c.relname AND p.policyname = #{connection.quote(POLICY_NAME)}
        WHERE c.relnamespace = current_schema()::regnamespace AND c.relrowsecurity
        ORDER BY c.relname
      SQL
    end

    # Consistency guard between "has an organization_id column" and "is registered as tenant" (has the
    # tenant_isolation policy). Returns the tables that break each direction; `exempt:` lists tables excluded on purpose.
    def inconsistencies(connection = ActiveRecord::Base.connection, exempt: [])
      exempt = exempt.map(&:to_s)
      # pg_attribute, not information_schema.columns: the latter only lists tables the current role has a privilege on,
      # so a table without a GRANT to app_user would go unnoticed.
      with_column = connection.select_values(<<~SQL)
        SELECT c.relname FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        WHERE c.relnamespace = current_schema()::regnamespace AND c.relkind IN ('r', 'p') AND NOT c.relispartition
          AND a.attname = 'organization_id' AND a.attnum > 0 AND NOT a.attisdropped
      SQL
      registered = names(connection)
      {
        unregistered: (with_column - registered - exempt).sort,
        without_organization_id: (registered - with_column - exempt).sort
      }
    end

    def tenant?(table_name, connection = ActiveRecord::Base.connection)
      names(connection).include?(table_name.to_s)
    end
  end
end
