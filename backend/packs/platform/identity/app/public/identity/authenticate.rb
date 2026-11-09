module Identity
  # Inicio de sesión con correo y contraseña (ADR-0017).
  #
  #   result = Identity::Authenticate.call(email:, password:, ip:, user_agent:, previous_token: cookie)
  #   result.token            # token en claro: va a la cookie y no se guarda en ningún otro sitio
  #   result.current_session  # Identity::CurrentSession
  #
  # - Lanza Identity::InvalidCredentials con correo inexistente o contraseña errónea (misma clase, mismo mensaje).
  # - Tiempo constante: `authenticate_by` calcula bcrypt también cuando la cuenta no existe, así el tiempo de respuesta
  #   no revela si el correo tiene cuenta.
  # - Rotación: el login SIEMPRE emite un token nuevo y revoca la sesión que el navegador traía (aunque fuera de otro
  #   usuario), así un token fijado antes del login no sirve después (fijación de sesión).
  class Authenticate
    Result = Data.define(:token, :current_session)

    def self.call(...) = new(...).call

    def initialize(email:, password:, ip: nil, user_agent: nil, previous_token: nil, now: Time.current)
      @email = email.to_s
      @password = password.to_s
      @ip = ip
      @user_agent = user_agent
      @previous_token = previous_token
      @now = now
    end

    def call
      user = User.authenticate_by(email: @email, password: @password)
      raise InvalidCredentials, "Credenciales inválidas" unless user

      session = Session.transaction do
        Session.find_active_by_token(@previous_token, now: @now)&.revoke!(now: @now)
        Session.issue!(user:, ip: @ip, user_agent: @user_agent, now: @now)
      end
      Result.new(token: session.token, current_session: CurrentSession.new(session))
    end
  end
end
