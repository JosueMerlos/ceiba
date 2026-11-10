module Modules
  # A module's controllers answer 404 when the module is not active in the context's company: the same 404 as a missing
  # resource, so it does not reveal the module exists. Checked BEFORE authorization.
  #
  #   class Api::V1::Appointments::AppointmentsController < Api::BaseController
  #     include Modules::RequiresModule
  #     requires_module :appointments
  #   end
  #
  # Uses the same per-request memoized query as `can?`, so a request does not hit company_modules twice. A route without a
  # company in the context also gets 404: there is nowhere to be active.
  module RequiresModule
    extend ActiveSupport::Concern

    included do
      class_attribute :required_module, instance_writer: false
      before_action :ensure_required_module_enabled!
    end

    class_methods do
      def requires_module(key)
        raise UnknownModule, key unless Modules.registry.key?(key)

        self.required_module = key.to_s
      end
    end

    private

    # Fail CLOSED: including the concern without declaring the module is a code bug, not open access.
    def ensure_required_module_enabled!
      raise Error, "#{self.class.name} incluye Modules::RequiresModule pero no declara `requires_module :clave`" if required_module.nil?

      company = Current.context&.company
      return if company && module_enabled_in?(company)

      # Internal marker (not in the response): lets the coverage suite tell this gate's 404 from an unknown route id.
      ActiveSupport::Notifications.instrument("denied.requires_module", module: required_module, controller: self.class.name, action: action_name)
      raise ActiveRecord::RecordNotFound, "No se encontró el recurso"
    end

    def module_enabled_in?(company)
      principal = Current.principal
      return principal.module_active?(required_module, company.id) if principal.respond_to?(:module_active?)

      Modules.enabled?(company, required_module)
    end
  end
end
