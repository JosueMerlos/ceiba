module Appointments
  # Importing professionals creates company records: the same company-level permission as creating them one by one.
  class ProfessionalImportPolicy < Access::BasePolicy
    def create? = can?("appointments.professional.manage", context_scope(:company))
    def show? = create?
  end
end
