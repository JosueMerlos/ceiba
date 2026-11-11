module Customers
  # Customers are company records managed from a branch: every permission is asked at the scope of the branch the staff
  # acts from (the route's), so a company_manager passes through the engine's downward rule.
  class CustomerPolicy < Access::BasePolicy
    def index? = can?("platform.customer.read", context_scope(:branch))
    def show? = can?("platform.customer.read", context_scope(:branch))
    def create? = can?("platform.customer.create", context_scope(:branch))
    def update? = can?("platform.customer.update", context_scope(:branch))
    def destroy? = can?("platform.customer.archive", context_scope(:branch))

    class Scope < Access::BasePolicy::Scope
      def resolve = principal.can?("platform.customer.read", context_scope(:branch)) ? scope : scope.none
    end
  end
end
