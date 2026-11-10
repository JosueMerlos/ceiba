# Global reset of "request" state between examples. Rails resets it on its own when a request or job ends, but a spec
# that opens `Tenancy.with_context` or assigns `Current.principal` without going through a request leaves that state
# alive for the next one (ActiveSupport::CurrentAttributes is not reset in service specs): `--seed 5718` made
# log_fields_spec fail with a foreign organization_id. It is cleaned AFTER each example (an `after` does not clobber the
# `around`/`before` hooks that set up a spec's own context).
RSpec.configure do |config|
  config.after do
    ActiveSupport::CurrentAttributes.descendants.each(&:reset)
    ActsAsTenant.current_tenant = nil
  end
end
