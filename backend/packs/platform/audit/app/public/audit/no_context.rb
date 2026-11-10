module Audit
  # Audit.record without a tenancy context: no organization to attribute the event to. A programming error (the API
  # answers a generic 500); run the use case inside Tenancy.with_context.
  class NoContext < Error; end
end
