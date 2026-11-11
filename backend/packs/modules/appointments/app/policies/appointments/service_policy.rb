module Appointments
  # Services are company records: reading is asked at the company's scope (branch roles pass through from_descendants) and
  # writing needs the company-level manage permission.
  class ServicePolicy < Access::BasePolicy
    def index? = can?("appointments.service.read", context_scope(:company))
    def show? = can?("appointments.service.read", context_scope(:company))
    def create? = can?("appointments.service.manage", context_scope(:company))
    def update? = can?("appointments.service.manage", context_scope(:company))
    def destroy? = can?("appointments.service.manage", context_scope(:company))

    class Scope < Access::BasePolicy::Scope
      def resolve = principal.can?("appointments.service.read", context_scope(:company)) ? scope : scope.none
    end
  end
end
