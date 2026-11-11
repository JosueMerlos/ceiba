module Appointments
  # Professionals are company records: reading is asked at the company's scope (branch roles pass through from_descendants)
  # and writing needs the company-level manage permission. Seen from a branch, a person also reads their OWN profile with the
  # own-profile permission, when the record is linked to their user and assigned to that branch.
  class ProfessionalPolicy < Access::BasePolicy
    def index? = can?("appointments.professional.read", context_scope(:company))
    def show? = can?("appointments.professional.read", context_scope(:company))
    def create? = can?("appointments.professional.manage", context_scope(:company))
    def update? = can?("appointments.professional.manage", context_scope(:company))
    def destroy? = can?("appointments.professional.manage", context_scope(:company))

    def show_in_branch? = can?("appointments.professional.read", context_scope(:branch)) || own_profile?

    private

    def own_profile?
      can?("appointments.professional.read_own", context_scope(:branch)) && record.user_id.present? && record.user_id == principal.id &&
        record.branch_ids.include?(Current.context.branch.id)
    end

    class Scope < Access::BasePolicy::Scope
      def resolve = principal.can?("appointments.professional.read", context_scope(:company)) ? scope : scope.none
    end
  end
end
