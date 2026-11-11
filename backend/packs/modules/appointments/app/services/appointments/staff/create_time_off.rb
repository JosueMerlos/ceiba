module Appointments
  module Staff
    # Creates an absence of a professional or a resource. The owner comes from the caller (the route), never from the
    # attributes. Audited by id and interval: the reason is free text that may be private, so it never reaches the trail.
    module CreateTimeOff
      module_function

      def call(owner:, attributes:)
        Staff.reject_archived!(owner)
        time_off = TimeOff.new(attributes.with_indifferent_access.slice(*TimeOff::EDITABLE).merge(TimeOff.owner_attributes(owner), company_id: owner.company_id))
        SaveAudited.call(time_off, action: "time_off.created", fields: TIME_OFF_AUDITED_FIELDS)
      end
    end
  end
end
