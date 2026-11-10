module Observability
  # Makes every Tenancy.with_context leave its context in Observability::LogContext.
  #
  # Prepended to Tenancy instead of editing tenancy.rb: the tenancy pack knows nothing about logs, and the hook keeps
  # working with any `with_context` signature (it forwards arguments as-is). Installed by
  # config/initializers/structured_logging.rb in `to_prepare` (after each code reload in development).
  module TenancyHook
    def with_context(...)
      return super unless block_given?

      super do |context|
        Observability::LogContext.remember(context)
        yield context
      end
    end
  end
end
