module Appointments
  module Catalog
    # Sets a branch's override of a service. MERGE semantics: only the attributes present in `attributes` change (an explicit
    # nil clears that value); the others keep what the row has.
    #
    # The block authorizes the candidate (the row with the change applied, not yet saved) and runs against the CURRENT row,
    # locked for the write, so a permission is checked against what is really there and not against a stale read. A block
    # that raises aborts everything.
    #
    # An archived service takes no new overrides (base: archived); removing one stays allowed (see RemoveOverride).
    #
    # Two concurrent first writes race: the loser (the unique index, or the uniqueness validation when the winner already
    # committed) rolls back its savepoint and retries once as an update.
    module UpsertOverride
      module_function

      def call(service:, branch_id:, attributes:, &authorize)
        attempt(service:, branch_id:, attributes:, authorize:)
      rescue ActiveRecord::RecordNotUnique
        attempt(service:, branch_id:, attributes:, authorize:)
      rescue ActiveRecord::RecordInvalid => error
        raise unless error.record.errors.of_kind?(:service_id, :taken)

        attempt(service:, branch_id:, attributes:, authorize:)
      end

      def attempt(service:, branch_id:, attributes:, authorize:)
        ApplicationRecord.transaction(requires_new: true) do
          override = BranchServiceOverride.find_by(branch_id:, service_id: service.id)&.tap(&:lock!) ||
                     BranchServiceOverride.new(branch_id:, service_id: service.id, company_id: service.company_id)
          override.assign_attributes(attributes.with_indifferent_access.slice(*BranchServiceOverride::EDITABLE))
          authorize&.call(override)
          reject_archived(service, override)
          SaveAudited.call(override, action: "service_override.set", fields: BranchServiceOverride::EDITABLE,
                                     metadata: { branch_id: override.branch_id, service_id: override.service_id })
        end
      end
      private_class_method :attempt

      def reject_archived(service, override)
        return unless service.archived?

        override.errors.add(:base, :archived)
        raise ActiveRecord::RecordInvalid, override
      end
      private_class_method :reject_archived
    end
  end
end
