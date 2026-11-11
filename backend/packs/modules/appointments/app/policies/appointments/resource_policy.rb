module Appointments
  # Resources belong to a branch: every permission is asked at the scope of the branch the route names, so a branch role only
  # reaches its own branch.
  class ResourcePolicy < Access::BasePolicy
    def index? = can?("appointments.resource.read", context_scope(:branch))
    def show? = can?("appointments.resource.read", context_scope(:branch))
    def create? = can?("appointments.resource.manage", context_scope(:branch))
    def update? = can?("appointments.resource.manage", context_scope(:branch))
    def destroy? = can?("appointments.resource.manage", context_scope(:branch))

    class Scope < Access::BasePolicy::Scope
      def resolve = principal.can?("appointments.resource.read", context_scope(:branch)) ? scope : scope.none
    end
  end
end
