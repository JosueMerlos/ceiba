module Appointments
  # Write use cases of the service catalog. Each one is transactional and audited with before/after (nothing in a service
  # or an override is personal data).
  module Catalog
    SERVICE_FIELDS = (Service::EDITABLE + %w[archived_at]).freeze
  end
end
