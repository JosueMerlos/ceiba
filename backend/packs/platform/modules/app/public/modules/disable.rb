module Modules
  # Disables a module for a company in one transaction: sets `disabled_at`, runs `on_disable` and emits
  # platform.module_disabled.v1. Deletes NO data (row and settings, including branches', survive so re-enabling recovers them).
  # Idempotent. Refuses while another ACTIVE module of the company requires it (Modules::RequiredByOthers).
  class Disable < Activation
    def call
      ApplicationRecord.transaction(requires_new: true) do
        lock_company!
        row = locked_row
        next result(false) unless row&.active?

        ensure_not_required!
        row.update!(disabled_at: Time.current)
        run_hook(:on_disable, manifest.on_disable)
        publish("platform.module_disabled.v1")
        audit("module.disabled", row, before: true, after: false)
        result(true)
      end
    end

    private

    def ensure_not_required!
      dependents = Modules.registry.requirers_of(key).map(&:key) & active_keys
      raise RequiredByOthers.new(key, dependents) if dependents.any?
    end
  end
end
