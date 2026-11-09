require "rails_helper"

RSpec.describe "Modelos de platform/modules" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  it "CompanyModule: la fila activa no tiene disabled_at; valida el formato de la key y no duplica" do
    with_tenant(organization) do
      active = Modules::CompanyModule.create!(company_id: company.id, module_key: "sample", enabled_at: Time.current)

      expect(active).to be_active
      expect(Modules::CompanyModule.active).to contain_exactly(active)
      expect(Modules::CompanyModule.new(company_id: company.id, module_key: "sample", enabled_at: Time.current)).not_to be_valid
      expect(Modules::CompanyModule.new(company_id: company.id, module_key: "Mal", enabled_at: Time.current)).not_to be_valid
    end
  end

  it "CompanyModule: una fila desactivada deja de estar activa y no sale en .active" do
    with_tenant(organization) do
      row = Modules::CompanyModule.create!(company_id: company.id, module_key: "sample", enabled_at: Time.current, disabled_at: Time.current)

      expect(row).not_to be_active
      expect(Modules::CompanyModule.active).to be_empty
    end
  end

  it "BranchModuleSetting: guarda los overrides de una sucursal" do
    branch = create_in(organization, :branch, company:)
    with_tenant(organization) do
      create(:company_module, company_id: company.id, module_key: "sample")
      setting = Modules::BranchModuleSetting.create!(company_id: company.id, branch_id: branch.id, module_key: "sample", settings: { "a" => 1 })

      expect(setting.reload.settings).to eq("a" => 1)
    end
  end
end
