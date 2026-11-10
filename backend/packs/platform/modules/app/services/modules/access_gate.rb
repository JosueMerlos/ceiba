module Modules
  # El gate que modules entrega a access (`Access.module_gate`): access pregunta, aquí se responde desde company_modules y el
  # registro de manifiestos. Devuelve qué empresas de la organización activa tienen cada módulo ENCENDIDO con UNA consulta
  # (acotada por el tenant, índice parcial idx_company_modules_active); el principal la memoiza por request.
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
