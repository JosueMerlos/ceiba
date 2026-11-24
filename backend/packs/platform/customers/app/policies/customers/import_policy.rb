module Customers
  # Importing customers loads (and may overwrite) many people at once, and its preview shows their phones and emails: it
  # needs the import permission AND customer read, at the scope of the branch the staff acts from.
  class ImportPolicy < Access::BasePolicy
    def create? = can?("platform.customer.import", context_scope(:branch)) && can?("platform.customer.read", context_scope(:branch))
    def show? = create?
  end
end
