module Appointments
  # Write use cases for the people who attend and the places they attend in: professionals, the branches they are assigned
  # to and the services they perform, resources, weekly hours and absences. Each one is transactional and audited with
  # before/after. The trail holds ids and operational fields only: the linked user is an id (never an email), the professional's
  # display name is recorded as a staff work name, and an absence's free-text reason is never recorded.
  module Staff
    PROFESSIONAL_FIELDS = (Professional::EDITABLE + %w[archived_at]).freeze
    RESOURCE_FIELDS = (Resource::EDITABLE + %w[archived_at]).freeze
    TIME_OFF_AUDITED_FIELDS = %w[owner_type professional_id resource_id starts_at ends_at].freeze

    # Anything archived (professional, resource or service) is read-only history: no write path may touch what hangs from it
    # (base: archived). Owners that cannot be archived (a branch) pass.
    def self.reject_archived!(owner)
      return unless owner.try(:archived?)

      owner.errors.add(:base, :archived)
      raise ActiveRecord::RecordInvalid, owner
    end
  end
end
