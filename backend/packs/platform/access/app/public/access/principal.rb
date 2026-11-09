module Access
  # Quién actúa. La autorización pregunta al PRINCIPAL, no al usuario (docs/architecture/04-access-control.md): todos
  # responden `can?(permission_key, scope)` y se distinguen por `kind`.
  #
  #   User         panel (cookie de sesión): permisos por memberships
  #   System       jobs internos
  #   ApiKey       integraciones (Bearer): M4.02, hoy solo la interfaz
  #   PublicToken  cliente final con enlace firmado: M3.04, hoy solo la interfaz
  #
  # (PlatformStaff, el operador de plataforma, llega con el back-office, M4.01.)
  module Principal
    def can?(_permission_key, _scope) = raise(NotImplementedError, "#{self.class} debe implementar can?(permission_key, scope)")
    def kind = raise(NotImplementedError, "#{self.class} debe implementar kind")

    # Un permiso sin registrar es un bug del código que pregunta, no una denegación (criterio 8).
    def self.ensure_registered!(permission_key)
      raise UnknownPermission, permission_key unless Access.registered?(permission_key)
    end
  end
end
