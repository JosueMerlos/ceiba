module Tenancy
  # Base of Tenancy's domain errors: callers can rescue it without knowing the details.
  class Error < StandardError; end
end
