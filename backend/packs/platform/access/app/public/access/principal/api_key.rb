module Access
  module Principal
    # Integraciones con API key (Bearer). SOLO LA INTERFAZ: la implementación (scopes `read:<modulo>` / `write:<modulo>`
    # traducidos a permisos) llega con M4.02. Mientras tanto niega todo: nada puede construir uno que autorice por error.
    class ApiKey
      include Principal

      def kind = :api_key

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        false
      end
    end
  end
end
