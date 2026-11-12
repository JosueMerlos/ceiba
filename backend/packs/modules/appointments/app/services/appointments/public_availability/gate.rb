module Appointments
  module PublicAvailability
    # The doors an anonymous availability request must pass, after the company has been opened from its slug: the company is
    # active, the branch is the company's and open, booking is enabled at BOTH levels (a branch setting can override the
    # company's, so reading only the merged branch value would let a branch re-open what the company closed), and the services
    # and the professional exist where they are searched. Anything else raises Closed. Must run inside a tenant context.
    module Gate
      Opening = Data.define(:branch, :services, :professional)

      module_function

      def open!(company:, branch_id:, service_ids:, professional_id:)
        branch = ::Tenancy::Directory.branch!(branch_id, company_id: company.id)
        raise Closed unless company.active? && branch.active? && booking_enabled?(company, branch)

        Opening.new(branch:, services: Service.where(company_id: company.id).in_order(service_ids),
                    professional: Availability::ProfessionalChoice.resolve(professional_id, within: Professional.assigned_to(branch)))
      end

      def booking_enabled?(company, branch)
        [ ::Modules.settings_for(:appointments, company:), ::Modules.settings_for(:appointments, company:, branch:) ].all? { it["public_booking_enabled"] == true }
      end
      private_class_method :booking_enabled?
    end
  end
end
