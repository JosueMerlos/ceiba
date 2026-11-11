module Appointments
  module Staff
    # Replaces ALL the weekly slots of an owner (the branch itself, a professional or a resource) in one branch: delete and
    # insert in one savepoint, so the editor sends the whole list of slots per day and either all of it applies or nothing.
    #
    # Overlaps are refused as `slots: overlap` (422), including against the same professional's hours in OTHER branches: the
    # model checks first and the exclusion constraint is the net, translated here because it aborts the transaction and so
    # must be rescued OUTSIDE the savepoint. Any other invalid slot is `slots: invalid`. An advisory lock per owner serializes
    # concurrent replacements: without it two simultaneous PUTs could both pass the check and leave the union of both sets.
    module ReplaceSchedule
      SLOT_FIELDS = %w[weekday starts_at_local ends_at_local].freeze

      # Carries the validation error of the whole replacement: there is no single row to blame.
      class Rejection
        include ActiveModel::Model

        attr_reader :slots

        def initialize(code)
          @slots = nil
          errors.add(:slots, code)
        end
      end

      module_function

      def call(owner:, branch_id:, slots:)
        ApplicationRecord.transaction(requires_new: true) { replace(owner, branch_id, slots) }
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(PG::ExclusionViolation)

        raise ActiveRecord::RecordInvalid, Rejection.new(:overlap)
      end

      def replace(owner, branch_id, slots)
        Staff.reject_archived!(owner)
        lock(owner)
        ownership = ownership_of(owner)
        current = WeeklySchedule.where(branch_id:, **ownership.fetch(:scope))
        before = describe(current)
        current.delete_all

        rows = slots.map { |slot| save!(slot, ownership.fetch(:attributes).merge(branch_id:, company_id: owner.company_id)) }

        after = describe(rows)
        Audit.record(action: "schedule.replaced", subject: owner, before: { "slots" => before }, after: { "slots" => after }, metadata: { branch_id:, owner_type: ownership.dig(:attributes, :owner_type) }) if before != after
        rows
      end
      private_class_method :replace

      def save!(slot, attributes)
        row = WeeklySchedule.new(slot.with_indifferent_access.slice(*SLOT_FIELDS).merge(attributes))
        row.save!
        row
      rescue ActiveRecord::RecordInvalid => error
        raise unless error.record.is_a?(WeeklySchedule)

        raise ActiveRecord::RecordInvalid, Rejection.new(error.record.errors.of_kind?(:base, :overlap) ? :overlap : :invalid)
      end
      private_class_method :save!

      def ownership_of(owner)
        case owner
        when Professional then { scope: { professional_id: owner.id }, attributes: { owner_type: "professional", professional_id: owner.id } }
        when Resource then { scope: { resource_id: owner.id }, attributes: { owner_type: "resource", resource_id: owner.id } }
        else { scope: { owner_type: "branch" }, attributes: { owner_type: "branch" } }
        end
      end
      private_class_method :ownership_of

      # By owner and not by owner and branch: a professional's exclusion constraint spans all their branches.
      def lock(owner)
        connection = ApplicationRecord.connection
        connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{connection.quote("ceiba.appointments.schedule:#{owner.id}")}))")
      end
      private_class_method :lock

      def describe(rows)
        rows.map { { "weekday" => it.weekday, "starts_at_local" => WeeklySchedule.clock(it.starts_at_local), "ends_at_local" => WeeklySchedule.clock(it.ends_at_local) } }
            .sort_by { [ it["weekday"], it["starts_at_local"] ] }
      end
      private_class_method :describe
    end
  end
end
