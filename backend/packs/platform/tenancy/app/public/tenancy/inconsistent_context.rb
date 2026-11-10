module Tenancy
  # The requested context mixes entities that do not fit (a company from another organization, a branch not in the given
  # company...). Raised BEFORE touching the tenant or the database.
  class InconsistentContext < Error; end
end
