require "rails_helper"

RSpec.describe "on_delete y nombres de restricciones", :tenant_schema do
  def delete_rule(owner, table, referenced)
    owner.select_value(<<~SQL)
      SELECT confdeltype FROM pg_constraint
      WHERE conrelid = #{owner.quote(table.to_s)}::regclass AND contype = 'f' AND confrelid = #{owner.quote(referenced.to_s)}::regclass
    SQL
  end

  it "restringe el borrado por defecto, tanto hacia organizations como entre tablas tenant" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:companies)
      owner.create_tenant_table(:branches) { |t| t.tenant_reference :company }

      expect([ delete_rule(owner, :companies, :organizations), delete_rule(owner, :branches, :companies) ]).to eq(%w[r r])
    end
  end

  it "acepta on_delete: :cascade en la referencia y hacia organizations" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:companies, on_delete: :cascade)
      owner.create_tenant_table(:branches) { |t| t.tenant_reference :company, on_delete: :cascade }

      expect([ delete_rule(owner, :companies, :organizations), delete_rule(owner, :branches, :companies) ]).to eq(%w[c c])
    end
  end

  it "borra en cascada de verdad" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:companies)
      owner.create_tenant_table(:branches) { |t| t.tenant_reference :company, on_delete: :cascade }
      org = new_organization(owner)
      company = owner.select_value("INSERT INTO companies (organization_id) VALUES ('#{org}') RETURNING id")
      owner.execute("INSERT INTO branches (organization_id, company_id) VALUES ('#{org}', '#{company}')")
      owner.execute("DELETE FROM companies WHERE id = '#{company}'")

      expect(owner.select_value("SELECT count(*) FROM branches")).to eq(0)
    end
  end

  it "rechaza :nullify: anularía organization_id, que es NOT NULL y parte de la FK compuesta" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:companies)

      expect { owner.create_tenant_table(:branches) { |t| t.tenant_reference :company, on_delete: :nullify } }
        .to raise_error(ArgumentError, /nullify.*restrict.*cascade/m)
      expect { owner.create_tenant_table(:things, on_delete: :nullify) }.to raise_error(ArgumentError, /nullify/)
    end
  end

  it "rechaza nombres de tabla que generan restricciones de más de 63 caracteres" do
    with_tenant_schema do |owner|
      long = "a" * 45

      expect { owner.create_tenant_table(long) }.to raise_error(ArgumentError, /63 caracteres/)
    end
  end

  it "rechaza una referencia cuya FK excede 63 caracteres" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:companies)
      reference = "r" * 60

      expect { owner.create_tenant_table(:branches) { |t| t.tenant_reference reference, to_table: :companies } }
        .to raise_error(ArgumentError, /63 caracteres/)
    end
  end
end
