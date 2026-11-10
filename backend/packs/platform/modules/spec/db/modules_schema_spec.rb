require "rails_helper"

# Esquema de platform/modules (M0.09, ADR-0010): company_modules y branch_module_settings son tablas TENANT y la BASE rechaza lo
# incoherente aunque el código se salte las validaciones.
RSpec.describe "Esquema de platform/modules" do
  let(:connection) { ApplicationRecord.connection }
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def quoted(*values) = values.map { |value| connection.quote(value) }.join(", ")

  # Inserta SIN validaciones ni callbacks: lo que cuenta es lo que decide la base.
  def insert_company_module(org: organization, company_id: company.id, module_key: "sample", settings: "{}")
    savepoint do
      connection.execute("INSERT INTO company_modules (organization_id, company_id, module_key, enabled_at, settings, created_at, updated_at) " \
                         "VALUES (#{quoted(org.id, company_id, module_key)}, now(), #{quoted(settings)}::jsonb, now(), now())")
    end
  end

  def insert_branch_setting(branch_id: branch.id, company_id: company.id, module_key: "sample", org: organization)
    savepoint do
      connection.execute("INSERT INTO branch_module_settings (organization_id, company_id, branch_id, module_key, settings, created_at, updated_at) " \
                         "VALUES (#{quoted(org.id, company_id, branch_id, module_key)}, '{}'::jsonb, now(), now())")
    end
  end

  it "ambas son tablas tenant (organization_id y política tenant_isolation)" do
    expect(Database::TenantTables.names).to include("company_modules", "branch_module_settings")
  end

  describe "company_modules" do
    it "admite una fila por (empresa, módulo): una segunda es rechazada por la base" do
      insert_company_module

      expect { insert_company_module }.to raise_error(ActiveRecord::RecordNotUnique, /uq_company_modules_company_module/)
    end

    it "admite el mismo módulo en otra empresa" do
      other = create_in(organization, :company)
      insert_company_module

      expect { insert_company_module(company_id: other.id) }.not_to raise_error
    end

    it "la empresa debe ser de la misma organización (FK compuesta)" do
      other_org = create(:organization)

      expect { insert_company_module(org: other_org) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_company_modules_company/)
    end

    it "rechaza una module_key que no es snake_case" do
      expect { insert_company_module(module_key: "Mal-Nombre") }.to raise_error(ActiveRecord::CheckViolation, /chk_company_modules_module_key/)
    end

    it "rechaza settings que no son un objeto JSON" do
      expect { insert_company_module(settings: "[1]") }.to raise_error(ActiveRecord::CheckViolation, /chk_company_modules_settings_object/)
    end

    it "no es una columna booleana por módulo en companies (ADR-0010)" do
      expect(connection.columns("companies").map(&:name)).to all(satisfy { |name| name.exclude?("module") })
    end
  end

  describe "tamaño de settings (sonda P3: un /me de 4,5 MB)" do
    let(:huge) { { "reminders" => Array.new(2_000) { |index| { "kind" => "recordatorio-#{index}", "offset_minutes" => index } } }.to_json }

    it "company_modules rechaza settings de más de 16 KB" do
      expect { insert_company_module(settings: huge) }.to raise_error(ActiveRecord::CheckViolation, /chk_company_modules_settings_size/)
    end

    it "branch_module_settings rechaza settings de más de 16 KB" do
      insert_company_module
      expect do
        savepoint do
          connection.execute("INSERT INTO branch_module_settings (organization_id, company_id, branch_id, module_key, settings, created_at, updated_at) " \
                             "VALUES (#{quoted(organization.id, company.id, branch.id, 'sample')}, #{quoted(huge)}::jsonb, now(), now())")
        end
      end.to raise_error(ActiveRecord::CheckViolation, /chk_branch_module_settings_settings_size/)
    end
  end

  describe "índice del gate" do
    it "el índice parcial de módulos activos empieza por organization_id (la consulta del gate está acotada por el tenant)" do
      index = connection.indexes("company_modules").find { |candidate| candidate.name == "idx_company_modules_active" }

      expect(index.columns).to eq(%w[organization_id module_key company_id])
      expect(index.where).to include("disabled_at IS NULL")
    end
  end

  describe "branch_module_settings" do
    before { insert_company_module }

    it "guarda los overrides de una sucursal de la empresa para un módulo que la empresa tiene" do
      expect { insert_branch_setting }.not_to raise_error
    end

    it "admite una fila por (sucursal, módulo)" do
      insert_branch_setting

      expect { insert_branch_setting }.to raise_error(ActiveRecord::RecordNotUnique, /uq_branch_module_settings_branch_module/)
    end

    it "exige que el módulo haya sido activado alguna vez en la empresa (FK compuesta a company_modules)" do
      expect { insert_branch_setting(module_key: "otro") }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_branch_module_settings_company_module/)
    end

    it "exige que la sucursal sea de ESA empresa (FK compuesta a branches)" do
      other_company = create_in(organization, :company)
      insert_company_module(company_id: other_company.id)

      expect { insert_branch_setting(company_id: other_company.id) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_branch_module_settings_branch/)
    end
  end
end
