module Observability
  # Where the "remembered" tenant of the current request or job lives, to write it to the log and Sentry AFTER the
  # Tenancy.with_context block has finished.
  #
  # Why it exists: a request's log line is written when the action ends, after an `around_action` with
  # `Tenancy.with_context` already exited and `Current.context` went back to nil. And a job that raises propagates the
  # exception out of the context before Sentry captures it. Filled by Observability::TenancyHook (every `with_context`)
  # and the jobs middleware; Rails resets it after each request or job (ActiveSupport::CurrentAttributes).
  #
  # Holds IDs, never entities: the log must not retain models.
  class LogContext < ActiveSupport::CurrentAttributes
    attribute :organization_id, :company_id, :branch_id, :job_class

    # Remembers the last opened context (the innermost one when nested).
    def self.remember(context)
      self.organization_id = context.organization&.id
      self.company_id = context.company&.id
      self.branch_id = context.branch&.id
    end
  end
end
