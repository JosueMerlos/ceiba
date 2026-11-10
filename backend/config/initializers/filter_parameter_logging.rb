# Be sure to restart your server when you modify this file.

# Parámetros que nunca llegan a un log ni a Sentry. Coincidencia PARCIAL de la clave (:passw filtra password,
# password_confirmation, new_password...). Usado por el log de Rails, por lograge y por el scrubber de Sentry.
# Ver ActiveSupport::ParameterFilter para las notaciones admitidas.
Rails.application.config.filter_parameters += [
  # Genéricos de Rails
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :ssn, :cvv, :cvc,
  # Contraseña (español incluido: "contraseña" y "contrasena")
  :contrase,
  # Segundo factor
  :otp,
  # Correo
  :email, :correo,
  # Teléfono
  :phone, :telefono, :teléfono, :celular, :mobile, :whatsapp,
  # Sesión y CSRF
  :csrf, :authorization, :cookie
]
