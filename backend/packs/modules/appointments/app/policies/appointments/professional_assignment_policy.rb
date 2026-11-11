module Appointments
  # Assigning a professional to a branch is asked at the scope of the branch the route names, so a branch role only reaches
  # its own branch. The record is the professional being assigned. A professional who already works ONLY in other branches is
  # not the branch role's to pull in (it would hand over their hours and absences): that takes the permission at COMPANY
  # scope. Removing is always from the route's branch.
  class ProfessionalAssignmentPolicy < Access::BasePolicy
    def upsert?
      can?("appointments.professional.assign", context_scope(:branch)) &&
        (record.available_to_branch?(Current.context.branch.id) || can?("appointments.professional.assign", context_scope(:company)))
    end

    def destroy? = can?("appointments.professional.assign", context_scope(:branch))
  end
end
