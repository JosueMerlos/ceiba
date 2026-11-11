module Appointments
  # Write use cases for the people who attend and the places they attend in: professionals, the branches they are assigned
  # to and the services they perform, resources, weekly hours and absences. Each one is transactional and audited with
  # before/after; nothing audited here is personal data (the linked user is an id, never an email or a name; an absence's
  # free-text reason is never recorded).
  module Staff
    PROFESSIONAL_FIELDS = (Professional::EDITABLE + %w[archived_at]).freeze
    RESOURCE_FIELDS = (Resource::EDITABLE + %w[archived_at]).freeze
    TIME_OFF_AUDITED_FIELDS = %w[owner_type professional_id resource_id starts_at ends_at].freeze

    # An archived professional or resource is read-only history: it takes no new hours or absences (base: archived). Owners
    # that cannot be archived (a branch) pass.
    def self.reject_archived!(owner)
      return unless owner.try(:archived?)

      owner.errors.add(:base, :archived)
      raise ActiveRecord::RecordInvalid, owner
    end
  end
end
