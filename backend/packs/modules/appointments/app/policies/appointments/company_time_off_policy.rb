module Appointments
  # Absences of a professional asked at the scope of the COMPANY, for the ones no branch route reaches (a professional with no
  # branch). The record is the professional. Only the company-wide permission opens it: a branch role, or a person's own
  # absences (`manage_own`), never pass through here.
  class CompanyTimeOffPolicy < Access::BasePolicy
    def index? = can?("appointments.time_off.read", context_scope(:company))
    def destroy? = can?("appointments.time_off.manage", context_scope(:company))

    class Scope < Access::BasePolicy::Scope
      def resolve = principal.can?("appointments.time_off.read", context_scope(:company)) ? scope : scope.none
    end
  end
end
