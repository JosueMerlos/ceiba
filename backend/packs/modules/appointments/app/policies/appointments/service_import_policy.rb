module Appointments
  # Importing services writes company records: the same company-level permission as creating them one by one.
  # One policy per kind, because a policy's permissions are written as literals.
  class ServiceImportPolicy < Access::BasePolicy
    def create? = can?("appointments.service.manage", context_scope(:company))
    def show? = create?
  end
end
