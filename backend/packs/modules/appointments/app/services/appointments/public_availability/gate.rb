module Appointments
  module PublicAvailability
    # The doors an anonymous availability request must pass, in two steps because the first must run before the query is read
    # (a malformed query must not tell an existing closed company from an unknown slug). The organization is checked when the
    # company is opened from its slug (Tenancy::PublicDirectory).
    #   open_company!: the company is active and booking is enabled in the company's own settings (a branch setting can
    #     override the company's, so the branch step alone would let a branch re-open what the company closed).
    #   open!: the branch is the company's and open, booking is enabled for it, and the services and the professional exist
    #     where they are searched. It relies on open_company! having run.
    # Anything else raises Closed. Must run inside a tenant context.
    module Gate
      Opening = Data.define(:branch, :services, :professional)

      module_function

      def open_company!(company)
        raise Closed unless company.active? && booking_enabled?(company)
      end

      def open!(company:, branch_id:, service_ids:, professional_id:)
        branch = ::Tenancy::Directory.branch!(branch_id, company_id: company.id)
        raise Closed unless branch.active? && booking_enabled?(company, branch)

        Opening.new(branch:, services: Service.where(company_id: company.id).in_order(service_ids),
                    professional: Availability::ProfessionalChoice.resolve(professional_id, within: Professional.assigned_to(branch)))
      end

      def booking_enabled?(company, branch = nil) = ::Modules.settings_for(:appointments, company:, branch:)["public_booking_enabled"] == true
      private_class_method :booking_enabled?
    end
  end
end
