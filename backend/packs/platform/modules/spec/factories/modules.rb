FactoryBot.define do
  # Created INSIDE a tenant (`create_in(org, :company_module, company_id: ...)`). organization_id comes from the active tenant;
  # company_id is required from the caller (the composite FK demands it belongs to that tenant).
  factory :company_module, class: "Modules::CompanyModule" do
    organization { ActsAsTenant.current_tenant }
    company_id { create(:company).id }
    module_key { "sample" }
    enabled_at { Time.current }
  end

  # The branch fixes the company; the module must be enabled in it (composite FK), so the factory creates it if needed.
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
