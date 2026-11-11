module Appointments
  module Staff
    # Creates an absence of a professional or a resource. The owner comes from the caller (the route), never from the
    # attributes. Audited by id and interval: the reason is free text that may be private, so it never reaches the trail.
    module CreateTimeOff
      module_function

      def call(owner:, attributes:)
        Staff.reject_archived!(owner)
        time_off = TimeOff.new(attributes.with_indifferent_access.slice(*TimeOff::EDITABLE).merge(owner_attributes(owner)))
        Catalog::SaveAudited.call(time_off, action: "time_off.created", fields: TIME_OFF_AUDITED_FIELDS)
      end

      def owner_attributes(owner)
        if owner.is_a?(Professional)
          { owner_type: "professional", professional_id: owner.id, company_id: owner.company_id }
        else
          { owner_type: "resource", resource_id: owner.id, company_id: owner.company_id }
        end
      end
      private_class_method :owner_attributes
    end
  end
end
