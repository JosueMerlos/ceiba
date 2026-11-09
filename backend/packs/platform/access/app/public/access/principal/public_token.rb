module Access
  module Principal
    # Cliente final con un enlace firmado de una cita (alcance mínimo). SOLO LA INTERFAZ: la implementación llega con M3.04.
    # Mientras tanto niega todo.
    class PublicToken
      include Principal

      def kind = :public_token

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        false
      end
    end
  end
end
