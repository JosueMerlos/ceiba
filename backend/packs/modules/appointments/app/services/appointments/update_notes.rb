module Appointments
  # Edits an appointment's notes under optimistic locking: `lock_version` is the version the client read, so an edit made over a change
  # it did not see (another edit, a status change) raises ActiveRecord::StaleObjectError (409 `resource.stale`). Blank notes clear
  # them. Audited, without the text, only when they change. A rescheduled appointment's notes were copied to the new one, which is
  # where they are edited (InvalidTransition): the version check guarantees the status did not change since the client read it.
  # Must run inside a tenant context.
  class UpdateNotes
    def self.call(appointment:, notes:, lock_version:, actor: Current.principal)
      raise InvalidTransition, "rescheduled" if appointment.status == "rescheduled"

      notes = notes.presence
      if notes && notes.length > Appointment::NOTES_MAX_LENGTH
        appointment.errors.add(:notes, :too_long, count: Appointment::NOTES_MAX_LENGTH)
        raise ActiveRecord::RecordInvalid, appointment
      end

      ApplicationRecord.transaction(requires_new: true) do
        appointment.lock_version = lock_version
        appointment.update!(notes:)
        if appointment.saved_change_to_notes?
          Audit.record(action: "appointments.appointment.notes_updated", subject: appointment, after: { notes: }, actor: actor || Access::Principal::System.new)
        end
      end
      appointment
    end
  end
end
