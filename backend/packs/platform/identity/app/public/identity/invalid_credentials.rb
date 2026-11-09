module Identity
  # Correo o contraseña incorrectos. Es UNA sola clase para "no existe la cuenta" y "contraseña errónea": quien llama no
  # puede distinguirlas, así la API no revela qué correos tienen cuenta (docs/architecture/11-security.md).
  class InvalidCredentials < Error; end
end
