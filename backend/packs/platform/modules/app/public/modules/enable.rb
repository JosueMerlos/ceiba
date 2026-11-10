module Modules
  # Enables a module for a company in one transaction: checks entitlement and `requires`, creates or reactivates the row,
  # runs `on_enable` and emits platform.module_enabled.v1. Idempotent: if already active nothing changes (no hook, no event)
  # and it returns `changed: false`. Re-enabling reuses the row with its settings.
  #
  #   Tenancy.with_context(organization:) { Modules::Enable.call(company:, key: "appointments") }
  #
  # Raises Modules::UnknownModule, Modules::NotEntitled or Modules::RequirementsNotMet.
  class Enable < Activation
    def call
      raise NotEntitled, key unless Modules.entitled?(company, key)

      ApplicationRecord.transaction(requires_new: true) do
        lock_company!
        row = locked_row
        next result(false) if row&.active?

        ensure_requirements!
        row = activate(row)
        next result(false) unless row

        run_hook(:on_enable, manifest.on_enable)
        publish("platform.module_enabled.v1")
        audit("module.enabled", row, before: false, after: true)
        result(true)
      end
    end

    private

    def ensure_requirements!
      missing = manifest.requires - active_keys
      raise RequirementsNotMet.new(key, missing) if missing.any?
    end

    # Returns nil when another transaction got there first (this call is a repeat).
    def activate(row)
      return row.tap { row.update!(enabled_at: Time.current, disabled_at: nil) } if row

      create_row
    end

    # If another transaction created the row between the read and the INSERT, the UNIQUE index rejects ours and that one wins.
    def create_row
      ApplicationRecord.transaction(requires_new: true) do
        CompanyModule.create!(company_id: company.id, module_key: key, enabled_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue ActiveRecord::RecordInvalid => error
      # The model's uniqueness validation fires before the UNIQUE index when the other transaction already committed.
      raise unless error.record.errors.of_kind?(:module_key, :taken)

      nil
    end
  end
end
