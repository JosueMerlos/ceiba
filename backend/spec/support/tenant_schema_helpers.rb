# Utilities for the DB convention specs. Everything happens on an owner connection inside a rolled-back transaction, and
# in a separate test SCHEMA (`tenant_probe`, with a minimal `organizations`): the real organizations/companies/branches
# tables exist in `public` and the test ones must not clash with them. Every catalog the helpers query uses
# current_schema(), so it keeps working.
module TenantSchemaHelpers
  def with_tenant_schema(&block)
    ActiveRecord::Migration.suppress_messages do
      OwnerConnection.rolled_back do |owner|
        owner.execute("CREATE SCHEMA tenant_probe")
        owner.execute("SET LOCAL search_path TO tenant_probe")
        owner.execute("CREATE TABLE organizations (id uuid PRIMARY KEY DEFAULT uuidv7(), name text)")
        instance_exec(owner, &block)
      end
    end
  end

  def new_organization(connection, name = "Org")
    connection.select_value("INSERT INTO organizations (name) VALUES (#{connection.quote(name)}) RETURNING id")
  end

  def column_info(connection, table, column)
    connection.select_one(<<~SQL)
      SELECT data_type, is_nullable, column_default FROM information_schema.columns
      WHERE table_schema = current_schema() AND table_name = #{connection.quote(table.to_s)} AND column_name = #{connection.quote(column.to_s)}
    SQL
  end

  # Columns (in order) of a table's constraints of one type ('u' unique, 'f' foreign).
  def constraint_columns(connection, table, type)
    connection.select_rows(<<~SQL).map { |name, columns| [ name, columns.delete("{}").split(",") ] }
      SELECT c.conname, (SELECT array_agg(a.attname ORDER BY k.ord)
                         FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                         JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum)
      FROM pg_constraint c WHERE c.conrelid = #{connection.quote(table.to_s)}::regclass AND c.contype = #{connection.quote(type)}
    SQL
  end

  def policy_for(connection, table)
    connection.select_one(<<~SQL)
      SELECT policyname, cmd, permissive, qual, with_check FROM pg_policies
      WHERE schemaname = current_schema() AND tablename = #{connection.quote(table.to_s)}
    SQL
  end

  def rls_flags(connection, table)
    connection.select_one(<<~SQL)
      SELECT relrowsecurity AS enabled, relforcerowsecurity AS forced FROM pg_class WHERE oid = #{connection.quote(table.to_s)}::regclass
    SQL
  end
end

RSpec.configure { |config| config.include TenantSchemaHelpers, :tenant_schema }
