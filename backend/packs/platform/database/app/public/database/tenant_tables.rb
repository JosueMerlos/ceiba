module Database
  # Registro de las tablas tenant (docs/architecture/09-data-conventions.md, "Tablas tenant").
  #
  # Una tabla es tenant si `create_tenant_table` le creó la política `tenant_isolation`: el registro se
  # DERIVA del catálogo de PostgreSQL (pg_policies) en vez de duplicarse en una tabla propia, así no
  # puede desincronizarse, viaja dentro de db/structure.sql y no necesita migraciones extra.
  #
  # Lo usan la suite de aislamiento (M0.05) y la migración que activa RLS en todas las tablas (M4.03).
  module TenantTables
    POLICY_NAME = "tenant_isolation".freeze

    module_function

    # Nombres de todas las tablas tenant del esquema actual, ordenados.
    def names(connection = ActiveRecord::Base.connection)
      connection.select_values(<<~SQL)
        SELECT tablename FROM pg_policies
        WHERE schemaname = current_schema() AND policyname = #{connection.quote(POLICY_NAME)}
        ORDER BY tablename
      SQL
    end

    # Tablas tenant que ya tienen RLS activado (M4.03 las activa todas).
    def rls_enabled(connection = ActiveRecord::Base.connection)
      connection.select_values(<<~SQL)
        SELECT c.relname FROM pg_class c
        JOIN pg_policies p ON p.schemaname = current_schema() AND p.tablename = c.relname AND p.policyname = #{connection.quote(POLICY_NAME)}
        WHERE c.relnamespace = current_schema()::regnamespace AND c.relrowsecurity
        ORDER BY c.relname
      SQL
    end

    def tenant?(table_name, connection = ActiveRecord::Base.connection)
      names(connection).include?(table_name.to_s)
    end
  end
end
