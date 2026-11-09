module Access
  # Se preguntó por un permiso que ningún pack registró (Access.register_permissions). Es un BUG del código que pregunta
  # (typo, permiso olvidado), no una denegación: se lanza en todos los entornos para que un permiso sin registrar nunca
  # "niegue en silencio" y falle la suite (criterio 8). La API lo responde como 500 genérico.
  class UnknownPermission < Error
    def initialize(key) = super("El permiso #{key.inspect} no está registrado: declara con Access.register_permissions")
  end
end
