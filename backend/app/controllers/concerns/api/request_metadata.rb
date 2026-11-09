module Api
  # Datos de la request que la auditoría anota (M0.11): request_id, IP y user agent, en Current. Va en Api::BaseController
  # antes que la autenticación para que estén disponibles en cualquier caso de uso, incluido el login. `remote_ip` es la
  # del cliente según el proxy confiable (no se lee X-Forwarded-For a mano).
  module RequestMetadata
    extend ActiveSupport::Concern

    included do
      before_action :capture_request_metadata
    end

    private

    def capture_request_metadata
      Current.request_id = request.request_id
      Current.ip = request.remote_ip
      Current.user_agent = request.user_agent
    end
  end
end
