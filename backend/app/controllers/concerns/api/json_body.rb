module Api
  # Las mutaciones de la API con cuerpo solo aceptan `application/json`; otro tipo (formulario urlencoded, multipart,
  # text/plain) responde 415 problem+json. Un formulario HTML de otro sitio solo puede enviar esos tipos "simples", así
  # que esto cierra, además de SameSite/Origin/CSRF, la vía de los POST cross-site sin preflight.
  #
  # Una mutación SIN cuerpo (DELETE /auth/logout) no necesita Content-Type. Corre ANTES que Origin y la autenticación.
  module JsonBody
    extend ActiveSupport::Concern

    SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

    included do
      before_action :require_json_body!
    end

    private

    def require_json_body!
      return if SAFE_METHODS.include?(request.request_method)
      return unless request.content_length.to_i.positive? || request.headers["Transfer-Encoding"].present?
      return if request.media_type == "application/json"

      raise UnsupportedMediaType, "Las mutaciones de la API solo aceptan application/json"
    end
  end
end
