module Idempotency
  # The idempotent endpoint ran without a tenancy context: no organization to attribute the key to. A programming bug
  # (500); the context is opened BEFORE (Tenancy.with_context).
  class MissingContext < Error; end
end
