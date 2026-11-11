module Appointments
  module Staff
    # Replaces the set of resource kinds a service needs. Kinds that stay are kept; the rest are removed or created. An
    # unknown kind is a validation error on `kind` and nothing changes. The service row is locked so two concurrent
    # replacements apply one after the other, never merged.
    module SetResourceRequirements
      module_function

      def call(service:, kinds:)
        ApplicationRecord.transaction(requires_new: true) do
          service.lock!
          wanted = kinds.uniq
          current = ServiceResourceRequirement.where(service_id: service.id).to_a
          before = current.map(&:kind).sort

          current.reject { wanted.include?(it.kind) }.each(&:destroy!)
          (wanted - before).each { ServiceResourceRequirement.create!(service_id: service.id, company_id: service.company_id, kind: it) }

          after = wanted.sort
          Audit.record(action: "service.resource_requirements_set", subject: service, before: { "kinds" => before }, after: { "kinds" => after }) if before != after
        end
        service
      end
    end
  end
end
