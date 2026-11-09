module Api
  module V1
    module Identity
      # Inicio, consulta y cierre de la sesión del panel (docs/architecture/11-security.md).
      class SessionsController < ::Api::BaseController
        # PÚBLICO a propósito: es la puerta de entrada, todavía no hay sesión que exigir. Sigue protegido por la
        # validación de Origin; el rate limit por IP y correo llega con M0.13. Las demás acciones exigen sesión.
        skip_authentication! only: :create
        # Estas acciones operan sobre la PROPIA sesión del principal (no sobre un recurso de una organización): no hay nada que
        # autorizar más allá de estar autenticado.
        skip_authorization! reason: "login, sesión y logout operan sobre la propia sesión, no sobre recursos de una organización"

        def create
          email, password = params.expect(:email, :password)
          result = ::Identity::Authenticate.call(
            email:, password:, ip: request.remote_ip, user_agent: request.user_agent, previous_token: cookies[::Api::SessionCookie.name]
          )
          ::Api::SessionCookie.write(cookies, result.token, expires_at: result.current_session.expires_at)
          render_session(result.current_session)
        end

        def show = render_session(Current.session)

        def destroy
          Current.session.revoke!
          ::Api::SessionCookie.clear(cookies)
          head :no_content
        end

        def destroy_all
          Current.session.revoke_all!
          ::Api::SessionCookie.clear(cookies)
          head :no_content
        end

        private

        def render_session(current_session)
          render json: { data: ::Identity::AuthSessionSerializer.new(current_session).serializable_hash }
        end
      end
    end
  end
end
