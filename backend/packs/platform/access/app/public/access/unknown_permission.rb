module Access
  # A permission nobody registered (Access.register_permissions) was asked about. It is a BUG in the asking code (typo,
  # forgotten permission), not a denial: it raises in every environment so an unregistered permission never "denies
  # silently" and the suite fails. The API answers it as a generic 500.
  class UnknownPermission < Error
    def initialize(key) = super("El permiso #{key.inspect} no está registrado: declara con Access.register_permissions")
  end
end
