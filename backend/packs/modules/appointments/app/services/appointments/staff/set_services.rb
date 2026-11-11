module Appointments
  module Staff
    # Replaces the set of services a professional performs. Links that stay in the set are kept; the rest are removed or
    # created. A service of another company (or unknown) is a validation error on `service_ids` and nothing changes. The
    # professional row is locked so two concurrent replacements apply one after the other, never merged.
    module SetServices
      module_function

      def call(professional:, service_ids:)
        ApplicationRecord.transaction(requires_new: true) do
          professional.lock!
          wanted = service_ids.uniq
          reject_unknown(professional, wanted)
          current = ProfessionalService.where(professional_id: professional.id).to_a
          before = current.map(&:service_id).sort

          current.reject { wanted.include?(it.service_id) }.each(&:destroy!)
          (wanted - before).each { link(professional, it) }
          professional.professional_services.reset

          after = wanted.sort
          Audit.record(action: "professional.services_set", subject: professional, before: { "service_ids" => before }, after: { "service_ids" => after }) if before != after
        end
        professional
      end

      def reject_unknown(professional, wanted)
        known = Service.where(company_id: professional.company_id, id: wanted).pluck(:id)
        return if (wanted - known).empty?

        professional.errors.add(:service_ids, :invalid)
        raise ActiveRecord::RecordInvalid, professional
      end
      private_class_method :reject_unknown

      def link(professional, service_id)
        ProfessionalService.create!(professional_id: professional.id, service_id:, company_id: professional.company_id)
      end
      private_class_method :link
    end
  end
end
