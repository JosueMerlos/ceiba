module Appointments
  # Write use cases for the people who attend: professionals, the branches they are assigned to and the services they
  # perform. Each one is transactional and audited with before/after; nothing audited here is personal data (the linked
  # user is an id, never an email or a name).
  module Staff
    PROFESSIONAL_FIELDS = (Professional::EDITABLE + %w[archived_at]).freeze
  end
end
