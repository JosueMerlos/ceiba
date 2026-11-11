module Appointments
  module Catalog
    # Removes a branch's override (the branch goes back to the service's own values). The block receives the CURRENT row,
    # reloaded under lock, to authorize against what is really there; a block that raises deletes nothing. A row another
    # request already removed raises ActiveRecord::RecordNotFound.
    module RemoveOverride
      module_function

      def call(override:)
        ApplicationRecord.transaction(requires_new: true) do
          override.lock!
          yield override if block_given?
          override.destroy!
          Audit.record(action: "service_override.removed", subject: override, before: override.attributes.slice(*BranchServiceOverride::EDITABLE),
                       metadata: { branch_id: override.branch_id, service_id: override.service_id })
        end
        override
      end
    end
  end
end
