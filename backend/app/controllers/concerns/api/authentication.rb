module Api
  # Autenticación y CSRF del panel (M0.07). DENY BY DEFAULT: este concern está incluido en Api::BaseController, así que
  # TODO controlador de la API exige sesión salvo que lo diga explícitamente con `skip_authentication!`.
  #
  #   class SessionsController < Api::BaseController
  #     # Es la puerta de entrada: aún no hay sesión. Origin se sigue validando.
  #     skip_authentication! only: :create
  #   end
  #
  # Orden de los filtros (el de declaración):
  #   1. verify_origin!     mutación con Origin/Referer ajeno -> 403 (con o sin sesión)
  #   2. authenticate!      sin sesión válida -> 401
  #   3. verify_csrf_token! mutación con sesión sin X-CSRF-Token válido -> 403
  #
  # `Current.session` y `Current.principal` quedan fijados al autenticar.
  module Authentication
    extend ActiveSupport::Concern

    CSRF_HEADER = "X-CSRF-Token".freeze
    SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

    included do
      # En modo API ActionController::API no incluye el helper `cookies` (el middleware sí se añade en
      # config/initializers/authentication.rb).
      include ActionController::Cookies

      before_action :verify_origin!
      before_action :authenticate!
      before_action :verify_csrf_token!
    end

    class_methods do
      # Hace PÚBLICO el controlador (o las acciones). Es una decisión de seguridad: comenta SIEMPRE por qué, y añade la
      # ruta a la allowlist de spec/requests/api/authentication_spec.rb. Sin sesión no hay token CSRF que exigir; el
      # Origin se valida igual.
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

    def verify_csrf_token!
      return if safe_method? || Current.session.nil?
      return if Current.session.valid_csrf_token?(request.headers[CSRF_HEADER])

      raise ::Identity::InvalidCsrfToken, "Falta el token CSRF o no es válido"
    end

    # Defensa en profundidad junto con SameSite=Lax y el token: un navegador envía `Origin` en toda mutación; si viene
    # (o su `Referer`) debe ser el origen propio. Sin ninguno de los dos (curl, clientes que no son navegadores) no se
    # rechaza aquí: sin token CSRF una mutación autenticada igual falla.
    def verify_origin!
      return if safe_method?

      source = request.origin.presence || origin_from(request.referer)
      return if source.blank? || source.casecmp?(request.base_url)

      raise ::Identity::ForbiddenOrigin, "El origen de la solicitud no es el propio"
    end

    def safe_method? = SAFE_METHODS.include?(request.request_method)

    def origin_from(referer)
      return if referer.blank?

      uri = URI.parse(referer)
      return "null" unless uri.scheme && uri.host

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port}"
    rescue URI::InvalidURIError
      "null"
    end
  end
end
