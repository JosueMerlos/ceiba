module Identity
  module Principal
    # Quién actúa en el panel: la persona autenticada por una sesión. MÍNIMO a propósito (M0.07): solo identidad.
    # Los memberships, los permisos y `can?(permission, scope)` llegan con M0.08 (`Access::Principal`), que lo envolverá
    # o lo reemplazará; hasta entonces nadie debe inferir autorización de este objeto.
    User = Data.define(:id, :email, :full_name) do
      # Contrato con la auditoría (M0.11): el tipo de actor.
      def actor_type = "user"
    end
  end
end
