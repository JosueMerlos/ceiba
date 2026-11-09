module Api
  # Autenticación y CSRF del panel (M0.07). DENY BY DEFAULT: este concern está incluido en Api::BaseController, así que
  # TODO controlador de la API exige sesión salvo que lo diga explícitamente con `skip_authentication!`.
  #
  #   class SessionsController < Api::BaseController
  #     # Es la puerta de entrada: aún no hay sesión. Origin se sigue validando.
  #     skip_authentication! only: :create
  #   end
  #
  # `Current.session` y `Current.principal` quedan fijados al autenticar.
  module Authentication
    extend ActiveSupport::Concern

    included do
      # En modo API ActionController::API no incluye el helper `cookies` (el middleware sí se añade en
      # config/initializers/authentication.rb).
      include ActionController::Cookies

      before_action :authenticate!
    end

    class_methods do
      # Hace PÚBLICO el controlador (o las acciones). Es una decisión de seguridad: comenta SIEMPRE por qué, y añade la
      # ruta a la allowlist de spec/requests/api/authentication_spec.rb.
      def skip_authentication!(**options)
        skip_before_action :authenticate!, **options
      end
    end

    private

    def authenticate!
      current = ::Identity::CurrentSession.resolve(cookies[SessionCookie.name])
      raise ::Identity::Unauthenticated, "No hay una sesión válida" unless current

      Current.session = current
      Current.principal = current.principal
    end
  end
end
