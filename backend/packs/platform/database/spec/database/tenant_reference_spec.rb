require "rails_helper"

# Criterio 3 de M0.04: una hija con un organization_id distinto al de su padre es rechazada por PostgreSQL
# (FK compuesta (organization_id, parent_id) -> parent(organization_id, id)). Barrera 2 de docs/architecture/03.
RSpec.describe "t.tenant_reference", :tenant_schema do
  def create_company_and_branch(owner, **reference_options)
    owner.create_tenant_table(:companies) { |t| t.string :name }
    owner.create_tenant_table(:branches) do |t|
      t.tenant_reference :company, **reference_options
      t.string :name
    end
  end

  it "agrega company_id uuid NOT NULL" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)

      expect(column_info(owner, :branches, :company_id)).to include("data_type" => "uuid", "is_nullable" => "NO")
    end
  end

  it "crea la FK compuesta (organization_id, company_id) -> companies (organization_id, id)" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)
      composite = owner.foreign_keys(:branches).find { |foreign_key| foreign_key.to_table == "companies" }

      expect(composite.column).to eq(%w[organization_id company_id])
      expect(composite.primary_key).to eq(%w[organization_id id])
    end
  end

  it "crea el índice (organization_id, company_id) para la FK" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)
      columns = owner.indexes(:branches).map(&:columns)

      expect(columns).to include(%w[organization_id company_id])
    end
  end

  it "acepta una hija del mismo tenant que su padre" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)
      org = new_organization(owner)
      company = owner.select_value("INSERT INTO companies (organization_id, name) VALUES ('#{org}', 'c') RETURNING id")

      expect { owner.execute("INSERT INTO branches (organization_id, company_id, name) VALUES ('#{org}', '#{company}', 'b')") }
        .not_to raise_error
    end
  end

  it "rechaza una hija cuyo organization_id difiere del de su padre (inserción cruzada)" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)
      org_a = new_organization(owner, "A")
      org_b = new_organization(owner, "B")
      company_of_a = owner.select_value("INSERT INTO companies (organization_id, name) VALUES ('#{org_a}', 'c') RETURNING id")

      expect { owner.execute("INSERT INTO branches (organization_id, company_id, name) VALUES ('#{org_b}', '#{company_of_a}', 'b')") }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_branches_company/)
    end
  end

  it "rechaza también mover una hija existente a otro tenant (UPDATE)" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner)
      org_a = new_organization(owner, "A")
      org_b = new_organization(owner, "B")
      company = owner.select_value("INSERT INTO companies (organization_id, name) VALUES ('#{org_a}', 'c') RETURNING id")
      branch = owner.select_value("INSERT INTO branches (organization_id, company_id, name) VALUES ('#{org_a}', '#{company}', 'b') RETURNING id")

      expect { owner.execute("UPDATE branches SET organization_id = '#{org_b}' WHERE id = '#{branch}'") }
        .to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "permite una referencia opcional con null: true" do
    with_tenant_schema do |owner|
      create_company_and_branch(owner, null: true)
      org = new_organization(owner)

      expect(column_info(owner, :branches, :company_id)).to include("is_nullable" => "YES")
      expect { owner.execute("INSERT INTO branches (organization_id, name) VALUES ('#{org}', 'b')") }.not_to raise_error
    end
  end

  it "permite apuntar a otra tabla con to_table y nombrar la columna con la referencia" do
    with_tenant_schema do |owner|
      owner.create_tenant_table(:professionals) { |t| t.string :name }
      owner.create_tenant_table(:appointments) { |t| t.tenant_reference :owner, to_table: :professionals }

      composite = owner.foreign_keys(:appointments).find { |foreign_key| foreign_key.to_table == "professionals" }
      expect(composite.column).to eq(%w[organization_id owner_id])
    end
  end

  it "solo existe dentro de create_tenant_table: en create_table normal no hay organization_id contra el que componer" do
    with_tenant_schema do |owner|
      expect { owner.create_table(:plain) { |t| t.tenant_reference :company } }.to raise_error(ArgumentError, /create_tenant_table/)
    end
  end
end
