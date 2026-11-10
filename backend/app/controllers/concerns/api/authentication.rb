module Api
  # Panel authentication and CSRF. Deny by default: included in Api::BaseController, so every API controller requires a
  # session unless it opts out explicitly with `skip_authentication!`.
  #
  #   class SessionsController < Api::BaseController
  #     # Entry point: there is no session yet. Origin is still validated.
  #     skip_authentication! only: :create
  #   end
  #
  # Filters run in declaration order:
  #   1. verify_origin!     mutation with a foreign Origin/Referer -> 403 (with or without session)
  #   2. authenticate!      no valid session -> 401
  #   3. verify_csrf_token! mutation with a session but no valid X-CSRF-Token -> 403
  #
  # `Current.session` and `Current.principal` are set on authentication.
  module Authentication
    extend ActiveSupport::Concern

    CSRF_HEADER = "X-CSRF-Token".freeze
    SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

    included do
      # ActionController::API does not include the `cookies` helper (the middleware is added in
      # config/initializers/authentication.rb).
      include ActionController::Cookies

      before_action :verify_origin!
      before_action :authenticate!
      before_action :verify_csrf_token!
    end

    class_methods do
      # Makes actions PUBLIC: always comment why, and add the route to the allowlist in authentication_spec.
      # Without a session there is no CSRF token to check; Origin is still validated.
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

    # Defense in depth with SameSite=Lax and the CSRF token: a present Origin (or Referer) must be in allowed_origins.
    # Host headers are spoofable, so unused. With neither header (curl), a missing CSRF token rejects the request anyway.
    def verify_origin!
      return if safe_method?

      source = request.origin.presence || origin_from(request.referer)
      return if source.blank? || allowed_origin?(source)

      raise ::Identity::ForbiddenOrigin, "El origen de la solicitud no es el propio"
    end

    def allowed_origin?(source) = Rails.configuration.x.auth.allowed_origins.include?(source.downcase)

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
