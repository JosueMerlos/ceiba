# Be sure to restart your server when you modify this file.

# Parameters that must never reach a log or Sentry. Keys match PARTIALLY (:passw filters password,
# password_confirmation, new_password...). Used by the Rails log, lograge and the Sentry scrubber.
Rails.application.config.filter_parameters += [
  # Rails defaults
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :ssn, :cvv, :cvc,
  # Password (Spanish included: "contraseña" and "contrasena")
  :contrase,
  # Second factor
  :otp,
  # Email
  :email, :correo,
  # Phone
  :phone, :telefono, :teléfono, :celular, :mobile, :whatsapp,
  # Free-text notes about a customer
  :notes,
  # A customer's name, in the body and in the name search of the listing. Never a bare :name or :q: they match every
  # unrelated parameter of that name, services and branches included.
  :full_name, :name_prefix,
  # Why someone is absent: free text that may reveal health or personal matters
  :reason,
  # Session and CSRF
  :csrf, :authorization, :cookie
]
