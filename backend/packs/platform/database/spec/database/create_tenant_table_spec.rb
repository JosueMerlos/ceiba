require "rails_helper"

# Criterio 2 de M0.04: `create_tenant_table` crea una tabla con organization_id NOT NULL, FK a organizations,
# UNIQUE(organization_id, id) y la política tenant_isolation registrada, con RLS deshabilitado.
RSpec.describe "create_tenant_table", :tenant_schema do
  def create_branches(owner)
    owner.create_tenant_table(:branches) do |t|
      t.string :name, null: false
      t.timestamps
    end
  end

  it "usa id uuid con default uuidv7()" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(column_info(owner, :branches, :id)).to include("data_type" => "uuid", "column_default" => "uuidv7()")
    end
  end

  it "agrega organization_id uuid NOT NULL" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(column_info(owner, :branches, :organization_id)).to include("data_type" => "uuid", "is_nullable" => "NO", "column_default" => nil)
    end
  end

  it "conserva las columnas del bloque" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(owner.columns(:branches).map(&:name)).to include("name", "created_at", "updated_at")
    end
  end

  it "crea la FK de organization_id a organizations" do
    with_tenant_schema do |owner|
      create_branches(owner)
      foreign_key = owner.foreign_keys(:branches).sole

      expect(foreign_key.to_table).to eq("organizations")
      expect(foreign_key.column).to eq("organization_id")
      expect { owner.execute("INSERT INTO branches (organization_id, name, created_at, updated_at) VALUES (uuidv7(), 'x', now(), now())") }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "declara UNIQUE (organization_id, id) para que otras tablas puedan referenciarla con FK compuesta" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(constraint_columns(owner, :branches, "u").map(&:last)).to eq([ %w[organization_id id] ])
    end
  end

  it "registra la política tenant_isolation con RLS deshabilitado" do
    with_tenant_schema do |owner|
      create_branches(owner)
      policy = policy_for(owner, :branches)

      expect(policy).to include("policyname" => "tenant_isolation", "cmd" => "ALL", "permissive" => "PERMISSIVE")
      expect(policy["qual"]).to include("organization_id", "app.organization_id")
      expect(policy["with_check"]).to eq(policy["qual"])
    end
  end

  it "deja RLS deshabilitado en la tabla (se activa en M4.03)" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(rls_flags(owner, :branches)).to eq("enabled" => false, "forced" => false)
    end
  end

  it "registra la tabla como tenant" do
    with_tenant_schema do |owner|
      create_branches(owner)

      expect(Database::TenantTables.names(owner)).to eq([ "branches" ])
      expect(Database::TenantTables.rls_enabled(owner)).to be_empty
    end
  end

  it "rechaza crear organizations como tabla tenant: es la raíz del tenant" do
    with_tenant_schema do |owner|
      expect { owner.create_tenant_table(:organizations) }.to raise_error(ArgumentError, /organizations/)
    end
  end

  it "rechaza un id distinto de uuidv7 y un organization_id declarado a mano" do
    with_tenant_schema do |owner|
      expect { owner.create_tenant_table(:things, id: :bigint) }.to raise_error(ArgumentError, /id/)
      expect { owner.create_tenant_table(:things) { |t| t.uuid :organization_id } }.to raise_error(ArgumentError, /organization_id/)
    end
  end

  it "es reversible en una migración (change): el down borra la tabla y su política" do
    with_tenant_schema do |owner|
      migration = Class.new(ActiveRecord::Migration[8.1]) do
        def change
          create_tenant_table(:branches) { |t| t.string :name }
        end
      end.new

      migration.exec_migration(owner, :up)
      expect(owner.table_exists?(:branches)).to be(true)

      migration.exec_migration(owner, :down)
      expect(owner.table_exists?(:branches)).to be(false)
      expect(Database::TenantTables.names(owner)).to be_empty
    end
  end
end
