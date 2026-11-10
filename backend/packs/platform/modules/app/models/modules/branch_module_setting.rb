module Modules
  # Branch-level settings overrides for a module (only keys allowed at branch level). Tenant table, private model.
  class BranchModuleSetting < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :company_id, :branch_id, presence: true
    validates :module_key, format: { with: CompanyModule::KEY_FORMAT }, uniqueness: { scope: :branch_id }
  end
end
