# Cabeceras de seguridad en toda respuesta (config/middleware/security_headers.rb). HSTS solo en producción: en desarrollo y
# test se sirve por HTTP y el navegador recordaría el host como "solo HTTPS". Rails (`force_ssl`) también puede emitirlo; este
# middleware pisa su valor para que haya UNA cabecera y con `preload`.
require Rails.root.join("config/middleware/security_headers").to_s

Rails.application.config.middleware.insert_before 0, SecurityHeaders, hsts: Rails.env.production?
