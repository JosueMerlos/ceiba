module Appointments
  module Staff
    # Deletes an absence for real: it has no history worth preserving. Audited by id and interval, never with the reason.
    module DeleteTimeOff
      module_function

      def call(time_off:)
        Staff.reject_archived!(time_off.professional || time_off.resource)
        ApplicationRecord.transaction(requires_new: true) do
          time_off.destroy!
          Audit.record(action: "time_off.deleted", subject: time_off, before: time_off.attributes.slice(*TIME_OFF_AUDITED_FIELDS))
        end
        time_off
      end
    end
  end
end
