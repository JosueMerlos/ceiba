module Identity
  # Mutación con sesión válida pero sin el token CSRF correcto en `X-CSRF-Token`. La API responde 403.
  class InvalidCsrfToken < Error; end
end
