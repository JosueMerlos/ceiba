module Access
  # Base of EVERY policy in the app: deny by default. Each policy lives in its pack, inherits from here and grants by
  # asking the PRINCIPAL for a permission in a scope, never by role name or `admin?` (enforced by the
  # Ceiba/AccessPolicyRoles cop):
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

    # An unregistered permission raises Access::UnknownPermission (a code bug, never a silent denial).
    def can?(permission_key, scope) = principal.can?(permission_key, scope)

    class Scope
      attr_reader :principal, :scope

      def initialize(principal, scope)
        @principal = principal
        @scope = scope
      end

      def resolve = scope.none

      private

      # What a permission reaches (Access::Reach), to filter the listing with a condition.
      def reach(permission_key) = principal.reach(permission_key)
    end
  end
end
