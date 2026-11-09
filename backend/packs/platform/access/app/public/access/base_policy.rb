module Access
  # Base de TODA policy de la aplicación (ADR-0007): niega por defecto. Cada policy vive en su pack, hereda de aquí y concede
  # preguntando al PRINCIPAL por un permiso en un alcance, nunca por un nombre de rol ni por `admin?` (el cop
  # Ceiba/AccessPolicyRoles lo vigila):
  #
  #   class Appointments::AppointmentPolicy < Access::BasePolicy
  #     def create? = can?("appointments.appointment.create", branch_scope)
  #
  #     class Scope < Access::BasePolicy::Scope
  #       def resolve
  #         reach = reach("appointments.appointment.read")
  #         reach.organization? ? scope : scope.where(branch_id: reach.branch_ids)
  #       end
  #     end
  #   end
  class BasePolicy
    attr_reader :principal, :record

    def initialize(principal, record)
      @principal = principal
      @record = record
    end

    %i[index show create new update edit destroy].each do |action|
      define_method(:"#{action}?") { false }
    end

    private

    # Un permiso sin registrar lanza Access::UnknownPermission (bug del código, nunca una denegación silenciosa).
    def can?(permission_key, scope) = principal.can?(permission_key, scope)

    class Scope
      attr_reader :principal, :scope

      def initialize(principal, scope)
        @principal = principal
        @scope = scope
      end

      # Por defecto no devuelve nada.
      def resolve = scope.none

      private

      # A qué llega un permiso (Access::Reach), para filtrar el listado con una condición.
      def reach(permission_key) = principal.reach(permission_key)
    end
  end
end
