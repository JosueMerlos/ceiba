module Modules
  # Returned by Enable and Disable. `changed` is false for a repeated call (no hook, no event).
  ActivationResult = Data.define(:key, :company_id, :changed)
end
