require "rails_helper"

# The application connects as `app_user` (not a table owner, no BYPASSRLS); migrations run as `app_owner`.
RSpec.describe "Roles de base de datos" do
  def select_value(sql) = ActiveRecord::Base.connection.select_value(sql)

  it "conecta la aplicación como app_user" do
    expect(select_value("SELECT current_user")).to eq("app_user")
  end

  it "app_user no es superusuario, no puede saltarse RLS y no puede crear bases ni roles" do
    flags = ActiveRecord::Base.connection.select_one(<<~SQL)
      SELECT rolsuper, rolbypassrls, rolcreatedb, rolcreaterole FROM pg_roles WHERE rolname = current_user
    SQL

    expect(flags.values).to all(be(false))
  end

  it "app_user no es dueño de ninguna tabla" do
    owned = select_value("SELECT count(*) FROM pg_tables WHERE tableowner = 'app_user'")

    expect(owned).to eq(0)
  end

  it "las tablas del esquema pertenecen a app_owner" do
    owners = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname = 'public'
    SQL

    expect(owners).to eq([ "app_owner" ])
  end

  it "app_user no puede ejecutar DDL: la aplicación no crea ni altera tablas" do
    expect { ActiveRecord::Base.connection.execute("CREATE TABLE roles_ddl_probe (id int)") }
      .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
  end

  it "app_owner (migraciones) no es superusuario ni BYPASSRLS" do
    OwnerConnection.with do |owner|
      flags = owner.select_one(<<~SQL)
        SELECT current_user AS name, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user
      SQL

      expect(flags).to eq("name" => "app_owner", "rolsuper" => false, "rolbypassrls" => false)
    end
  end

  it "las tablas creadas después por app_owner quedan accesibles para app_user (ALTER DEFAULT PRIVILEGES)" do
    OwnerConnection.with do |owner|
      owner.execute("CREATE TABLE roles_grant_probe (id uuid PRIMARY KEY DEFAULT uuidv7(), name text)")
      begin
        # Queried with has_table_privilege from the owner connection: using the suite's transactional connection would
        # leave a lock open on the table and the DROP would wait forever.
        privileges = %w[SELECT INSERT UPDATE DELETE].index_with do |privilege|
          owner.select_value("SELECT has_table_privilege('app_user', 'roles_grant_probe', '#{privilege}')")
        end
        ddl = %w[TRUNCATE REFERENCES TRIGGER].map do |privilege|
          owner.select_value("SELECT has_table_privilege('app_user', 'roles_grant_probe', '#{privilege}')")
        end

        expect(privileges.values).to all(be(true))
        expect(ddl).to all(be(false))
      ensure
        owner.execute("DROP TABLE roles_grant_probe")
      end
    end
  end
end
