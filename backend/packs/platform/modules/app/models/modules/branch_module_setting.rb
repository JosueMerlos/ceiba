module Modules
  # Overrides de settings de una sucursal para un módulo (solo claves permitidas a nivel sucursal). Tabla tenant, modelo PRIVADO.
  class BranchModuleSetting < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :company_id, :branch_id, presence: true
    validates :module_key, format: { with: CompanyModule::KEY_FORMAT }, uniqueness: { scope: :branch_id }
  end
end
