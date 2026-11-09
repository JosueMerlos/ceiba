module Access
  module Principal
    # Los jobs internos (relay, purgas, tareas programadas) actúan como el sistema: de confianza, sin pasar por memberships.
    # Ninguna request HTTP lo construye. Aun así, un permiso sin registrar sigue siendo un error.
    class System
      include Principal

      def kind = :system

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        true
      end
    end
  end
end
