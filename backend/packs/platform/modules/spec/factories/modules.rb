FactoryBot.define do
  # Como el resto de modelos tenant, se crean DENTRO de un tenant (`create_in(org, :company_module, company_id: ...)`).
  # organization_id sale del tenant activo; company_id es obligatorio y lo da quien llama (la FK compuesta exige que sea de ese tenant).
  factory :company_module, class: "Modules::CompanyModule" do
    organization { ActsAsTenant.current_tenant }
    company_id { create(:company).id }
    module_key { "sample" }
    enabled_at { Time.current }
  end

  # La sucursal fija la empresa; el módulo debe estar activado en ella (FK compuesta): la factory lo crea si hace falta.
  factory :branch_module_setting, class: "Modules::BranchModuleSetting" do
    organization { ActsAsTenant.current_tenant }
    branch_id { create(:branch).id }
    company_id { Tenancy::Directory.branch_company_id(branch_id) }
    module_key { "sample" }

    before(:create) do |setting|
      Modules::CompanyModule.find_or_create_by!(company_id: setting.company_id, module_key: setting.module_key) { |row| row.enabled_at = Time.current }
    end
  end
end
