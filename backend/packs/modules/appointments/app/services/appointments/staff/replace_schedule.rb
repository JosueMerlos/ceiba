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
      # Strict wall-clock minute: anything else ("24:00", "09:00-06:00") is cast by Rails onto another date or offset.
      CLOCK = /\A([01]\d|2[0-3]):[0-5]\d\z/

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

      def call(owner:, branch_id:, slots:, action: "schedule.replaced")
        ApplicationRecord.transaction(requires_new: true) { replace(owner, branch_id, slots, action) }
      rescue ActiveRecord::StatementInvalid => error
        raise ActiveRecord::RecordInvalid, Rejection.new(:overlap) if error.cause.is_a?(PG::ExclusionViolation)
        raise ActiveRecord::RecordInvalid, Rejection.new(:invalid) if error.is_a?(ActiveRecord::CheckViolation) || error.cause.is_a?(PG::CheckViolation)

        raise
      end

      def replace(owner, branch_id, slots, action)
        Staff.reject_archived!(owner)
        lock(owner)
        owner_attributes = WeeklySchedule.owner_attributes(owner)
        current = WeeklySchedule.where(branch_id:).owned_by(owner)
        before = describe(current)
        current.delete_all

        rows = slots.map { |slot| save!(slot, owner_attributes.merge(branch_id:, company_id: owner.company_id)) }

        after = describe(rows)
        Audit.record(action:, subject: owner, before: { "slots" => before }, after: { "slots" => after },
                     metadata: { branch_id:, company_id: owner.company_id, owner_type: owner_attributes.fetch(:owner_type) }) if before != after
        rows
      end
      private_class_method :replace

      def save!(slot, attributes)
        raise ActiveRecord::RecordInvalid, Rejection.new(:invalid) unless clock_slot?(slot)

        row = WeeklySchedule.new(slot.with_indifferent_access.slice(*SLOT_FIELDS).merge(attributes))
        row.save!
        row
      rescue ActiveRecord::RecordInvalid => error
        raise unless error.record.is_a?(WeeklySchedule)

        raise ActiveRecord::RecordInvalid, Rejection.new(error.record.errors.of_kind?(:base, :overlap) ? :overlap : :invalid)
      end
      private_class_method :save!

      def clock_slot?(slot)
        slot.with_indifferent_access.values_at("starts_at_local", "ends_at_local").all? { it.is_a?(String) && CLOCK.match?(it) }
      end
      private_class_method :clock_slot?

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
