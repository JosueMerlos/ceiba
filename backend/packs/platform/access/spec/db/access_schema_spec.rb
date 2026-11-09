require "rails_helper"

# Esquema de control de acceso (M0.08, ADR-0008). Qué es global y qué es tenant, y qué rechaza la BASE aunque el código se
# salte las validaciones (criterio 6: el CHECK de alcance).
RSpec.describe "Esquema de platform/access" do
  let(:connection) { ApplicationRecord.connection }
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { with_tenant(organization) { create(:branch, company:) } }
  let(:user_id) { create(:user).id }

  let(:levels) { { "org_admin" => "organization", "company_manager" => "company", "receptionist" => "branch" } }

  # Roles mínimos para este spec (el catálogo de sistema completo lo prueba catalog_sync_spec). Idempotente.
  def ensure_role(key)
    Access::Role.find_or_create_by!(key:) { |role| role.scope_level = levels.fetch(key) }
  end

  # Inserta un membership SIN pasar por validaciones ni callbacks: lo que cuenta es lo que decide la base.
  def insert_membership(role_key:, scope_level:, company_id: nil, branch_id: nil, org: organization)
    role = ensure_role(role_key)
    sql = <<~SQL.squish
      INSERT INTO memberships (organization_id, user_id, role_id, scope_level, company_id, branch_id, created_at, updated_at)
      VALUES (#{[ org.id, user_id, role.id, scope_level, company_id, branch_id ].map { |value| connection.quote(value) }.join(', ')}, now(), now())
    SQL
    savepoint { connection.execute(sql) }
  end

  describe "qué tablas son globales y cuáles tenant" do
    it "memberships es tenant (organization_id, política tenant_isolation)" do
      expect(Database::TenantTables.names).to include("memberships")
    end

    it "permissions, roles y role_permissions son GLOBALES: catálogo de plataforma, sin organization_id" do
      %w[permissions roles role_permissions].each do |table|
        expect(Database::TenantTables.names).not_to include(table)
        expect(connection.columns(table).map(&:name)).not_to include("organization_id")
      end
    end
  end

  describe "criterio 6: el CHECK de alcance de memberships" do
    it "rechaza un membership de sucursal sin company_id" do
      expect { insert_membership(role_key: "receptionist", scope_level: "branch", branch_id: branch.id) }
        .to raise_error(ActiveRecord::CheckViolation, /chk_memberships_scope/)
    end

    it "rechaza un membership de organización con company_id" do
      expect { insert_membership(role_key: "org_admin", scope_level: "organization", company_id: company.id) }
        .to raise_error(ActiveRecord::CheckViolation, /chk_memberships_scope/)
    end

    it "rechaza un membership de empresa sin company_id" do
      expect { insert_membership(role_key: "company_manager", scope_level: "company") }
        .to raise_error(ActiveRecord::CheckViolation, /chk_memberships_scope/)
    end

    it "rechaza un membership de empresa con branch_id" do
      expect { insert_membership(role_key: "company_manager", scope_level: "company", company_id: company.id, branch_id: branch.id) }
        .to raise_error(ActiveRecord::CheckViolation, /chk_memberships_scope/)
    end

    it "rechaza un scope_level desconocido" do
      expect { insert_membership(role_key: "org_admin", scope_level: "galaxia") }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "acepta las tres combinaciones válidas" do
      insert_membership(role_key: "org_admin", scope_level: "organization")
      insert_membership(role_key: "company_manager", scope_level: "company", company_id: company.id)
      insert_membership(role_key: "receptionist", scope_level: "branch", company_id: company.id, branch_id: branch.id)

      expect(connection.select_value("SELECT count(*) FROM memberships WHERE organization_id = #{connection.quote(organization.id)}")).to eq(3)
    end
  end

  describe "integridad referencial" do
    it "el scope_level del membership debe ser el del rol (FK compuesta a roles)" do
      expect { insert_membership(role_key: "org_admin", scope_level: "company", company_id: company.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_memberships_role_scope/)
    end

    it "la empresa debe ser de la misma organización" do
      other = create(:organization)
      foreign_company = create_in(other, :company)

      expect { insert_membership(role_key: "company_manager", scope_level: "company", company_id: foreign_company.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "la sucursal debe pertenecer a la empresa del membership (FK compuesta organización-empresa-sucursal)" do
      other_company = create_in(organization, :company)

      expect { insert_membership(role_key: "receptionist", scope_level: "branch", company_id: other_company.id, branch_id: branch.id) }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_memberships_branch/)
    end

    it "el usuario debe existir" do
      user_id_missing = "0198f0a0-0000-7000-8000-000000000000"
      role = ensure_role("org_admin")
      sql = "INSERT INTO memberships (organization_id, user_id, role_id, scope_level, created_at, updated_at) VALUES (#{[ organization.id, user_id_missing, role.id, 'organization' ].map { |v| connection.quote(v) }.join(', ')}, now(), now())"

      expect { savepoint { connection.execute(sql) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_memberships_user/)
    end

    it "no se repite el mismo rol del mismo usuario en el mismo alcance (también con NULL)" do
      insert_membership(role_key: "org_admin", scope_level: "organization")

      expect { insert_membership(role_key: "org_admin", scope_level: "organization") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "un permiso de un rol debe estar declarado (FK a permissions)" do
      role = ensure_role("org_admin")
      sql = "INSERT INTO role_permissions (role_id, permission_key, created_at, updated_at) VALUES (#{connection.quote(role.id)}, 'nada.no.existe', now(), now())"

      expect { savepoint { connection.execute(sql) } }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "la clave de un permiso es <modulo>.<recurso>.<accion> y empieza por su module_key" do
      bad_format = "INSERT INTO permissions (key, module_key, description, created_at, updated_at) VALUES ('mala', 'mala', 'x', now(), now())"
      bad_module = "INSERT INTO permissions (key, module_key, description, created_at, updated_at) VALUES ('a.b.c', 'otro', 'x', now(), now())"

      expect { savepoint { connection.execute(bad_format) } }.to raise_error(ActiveRecord::CheckViolation)
      expect { savepoint { connection.execute(bad_module) } }.to raise_error(ActiveRecord::CheckViolation)
    end
  end
end
