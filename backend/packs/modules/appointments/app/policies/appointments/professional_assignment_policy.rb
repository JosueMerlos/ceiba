module Appointments
  # Assigning a professional to a branch is asked at the scope of the branch the route names, so a branch role only reaches
  # its own branch. The record is the professional being assigned.
  class ProfessionalAssignmentPolicy < Access::BasePolicy
    def upsert? = can?("appointments.professional.assign", context_scope(:branch))
    def destroy? = can?("appointments.professional.assign", context_scope(:branch))
  end
end
