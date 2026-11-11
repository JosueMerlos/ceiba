module Appointments
  module Staff
    # Replaces the set of resource kinds a service needs. Kinds that stay are kept; the rest are removed or created. An
    # unknown kind is a validation error on `kind` and nothing changes. The service row is locked so two concurrent
    # replacements apply one after the other, never merged.
    module SetResourceRequirements
      # Carries `kinds: invalid`: the service has no `kinds` attribute to blame.
      class Rejection
        include ActiveModel::Model

        attr_reader :kinds

        def initialize
          @kinds = nil
          errors.add(:kinds, :invalid)
        end
      end

      module_function

      def call(service:, kinds:)
        Staff.reject_archived!(service)
        reject_unknown_kinds(kinds)
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

      # Up front, before any query: a kind outside the list (or one the database cannot even store, like a NUL byte) is the
      # caller's mistake, not something for the uniqueness check to trip over.
      def reject_unknown_kinds(kinds)
        return if kinds.all? { Resource::KINDS.include?(it) }

        raise ActiveRecord::RecordInvalid, Rejection.new
      end
      private_class_method :reject_unknown_kinds
    end
  end
end
