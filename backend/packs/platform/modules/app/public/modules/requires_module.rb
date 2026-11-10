module Modules
  # Los controladores de un módulo responden 404 si el módulo no está activo en la empresa del contexto (docs/architecture/05,
  # "Cumplimiento"): el mismo 404 que un recurso inexistente, sin revelar que el módulo existe. Se verifica ANTES de la autorización.
  #
  #   class Api::V1::Appointments::AppointmentsController < Api::BaseController
  #     include Modules::RequiresModule
  #     requires_module :appointments
  #   end
  #
  # Usa la misma consulta (memoizada por request) que `can?` para los permisos del módulo, así una request no consulta
  # company_modules dos veces. Una ruta sin empresa en el contexto también responde 404: no hay dónde estar activo.
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

    # Fallar CERRADO: incluir el concern sin declarar el módulo es un bug del código, no un acceso libre.
    def ensure_required_module_enabled!
      raise Error, "#{self.class.name} incluye Modules::RequiresModule pero no declara `requires_module :clave`" if required_module.nil?

      company = Current.context&.company
      return if company && module_enabled_in?(company)

      # Marca interna (no sale en la respuesta): la suite de cobertura de módulos comprueba que el 404 lo emitió ESTE gate y no un
      # id desconocido de la ruta.
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
