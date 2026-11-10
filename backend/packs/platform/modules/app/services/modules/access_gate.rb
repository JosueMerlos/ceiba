module Modules
  # The gate modules hands to access (`Access.module_gate`): answers from company_modules and the manifest registry. Returns
  # which companies of the active organization have each module ENABLED with ONE tenant-scoped query (partial index
  # idx_company_modules_active); the principal memoizes it per request.
  module AccessGate
    module_function

    def gated?(module_key) = Modules.registry.key?(module_key)

    def active_companies_by_module
      CompanyModule.active.pluck(:module_key, :company_id).each_with_object({}) do |(module_key, company_id), active|
        (active[module_key] ||= Set.new) << company_id
      end
    end
  end
end
