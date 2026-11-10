require "rails_helper"

# FORCE is used so the policy also applies to the table owner, which is the spec's own connection.
RSpec.describe "enable_tenant_rls", :tenant_schema do
  def create_branches(owner) = owner.create_tenant_table(:branches) { |t| t.string :name }

  it "activa RLS en la tabla y es reversible con disable_tenant_rls" do
    with_tenant_schema do |owner|
      create_branches(owner)

      owner.enable_tenant_rls(:branches)
      expect(rls_flags(owner, :branches)).to eq("enabled" => true, "forced" => false)
      expect(Database::TenantTables.rls_enabled(owner)).to eq([ "branches" ])

      owner.disable_tenant_rls(:branches)
      expect(rls_flags(owner, :branches)).to eq("enabled" => false, "forced" => false)
    end
  end

  it "con force: true también aplica al dueño de la tabla" do
    with_tenant_schema do |owner|
      create_branches(owner)

      owner.enable_tenant_rls(:branches, force: true)

      expect(rls_flags(owner, :branches)).to eq("enabled" => true, "forced" => true)
    end
  end

  it "rechaza tablas que no son tenant" do
    with_tenant_schema do |owner|
      owner.create_table(:plain)

      expect { owner.enable_tenant_rls(:plain) }.to raise_error(ArgumentError, /tenant/)
    end
  end

  it "es reversible en una migración (change)" do
    with_tenant_schema do |owner|
      create_branches(owner)
      migration = Class.new(ActiveRecord::Migration[8.1]) { def change = enable_tenant_rls(:branches) }.new

      migration.exec_migration(owner, :up)
      expect(rls_flags(owner, :branches)["enabled"]).to be(true)

      migration.exec_migration(owner, :down)
      expect(rls_flags(owner, :branches)["enabled"]).to be(false)
    end
  end

  describe "política tenant_isolation activada" do
    def set_tenant(owner, value) = owner.execute("SELECT set_config('app.organization_id', #{owner.quote(value)}, true)")

    it "solo deja ver y escribir filas del tenant fijado con app.organization_id" do
      with_tenant_schema do |owner|
        create_branches(owner)
        org_a = new_organization(owner, "A")
        org_b = new_organization(owner, "B")
        owner.execute("INSERT INTO branches (organization_id, name) VALUES ('#{org_a}', 'a'), ('#{org_b}', 'b')")
        owner.enable_tenant_rls(:branches, force: true)

        set_tenant(owner, org_a)
        expect(owner.select_values("SELECT name FROM branches")).to eq([ "a" ])
        expect { owner.execute("INSERT INTO branches (organization_id, name) VALUES ('#{org_b}', 'x')") }
          .to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
    end

    it "sin tenant fijado (o con el setting vacío tras un SET LOCAL previo) no devuelve filas ni falla" do
      with_tenant_schema do |owner|
        create_branches(owner)
        org = new_organization(owner)
        owner.execute("INSERT INTO branches (organization_id, name) VALUES ('#{org}', 'a')")
        owner.enable_tenant_rls(:branches, force: true)

        expect(owner.select_value("SELECT count(*) FROM branches")).to eq(0)

        set_tenant(owner, "")
        expect(owner.select_value("SELECT count(*) FROM branches")).to eq(0)
      end
    end
  end
end
