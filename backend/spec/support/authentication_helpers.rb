# Ayudas para specs de request con sesión (M0.07). El login es el REAL, por HTTP: lo que prueban los specs es el mismo
# camino que sigue el navegador (cookie + token CSRF), no un atajo que se salte la autenticación.
module AuthenticationHelpers
  DEFAULT_PASSWORD = "contraseña-segura-1".freeze

  # Lo que un navegador conserva tras iniciar sesión: la cookie (en su jar) y el token CSRF que devuelve la API.
  SignedIn = Data.define(:user, :csrf_token, :session_token) do
    def csrf_headers = { "X-CSRF-Token" => csrf_token }
  end

  # `browser:` es una sesión de integración (self, o `open_session` para simular OTRO navegador con su propio jar).
  def sign_in(user = nil, password: DEFAULT_PASSWORD, browser: self)
    user ||= create(:user, password:)
    browser.post "/api/v1/auth/login", params: { email: user.email, password: }, as: :json
    raise "sign_in falló: #{browser.response.status} #{browser.response.body}" unless browser.response.status == 200

    SignedIn.new(user:, csrf_token: browser.response.parsed_body.dig("data", "csrf_token"), session_token: browser.cookies[Api::SessionCookie.name])
  end
end

RSpec.configure { |config| config.include AuthenticationHelpers, type: :request }
