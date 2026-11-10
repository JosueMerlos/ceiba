module Api
  module V1
    module Identity
      # Sign-in, lookup and sign-out of the panel session.
      class SessionsController < ::Api::BaseController
        # PUBLIC on purpose: it is the entry point, there is no session to require yet. It is still protected by Origin
        # validation. The other actions require a session.
        skip_authentication! only: :create
        # These actions operate on the principal's OWN session (not on an organization's resource): there is nothing to
        # authorize beyond being authenticated.
        skip_authorization! reason: "login, sesión y logout operan sobre la propia sesión, no sobre recursos de una organización",
          only: %i[create show destroy destroy_all]

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
