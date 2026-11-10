# Helpers for request specs with a session. Login is the REAL one, over HTTP: the specs exercise the same path the
# browser follows (cookie + CSRF token), not a shortcut that skips authentication.
module AuthenticationHelpers
  DEFAULT_PASSWORD = "contraseña-segura-1".freeze

  # What a browser keeps after logging in: the cookie (in its jar) and the CSRF token the API returns.
  SignedIn = Data.define(:user, :csrf_token, :session_token) do
    def csrf_headers = { "X-CSRF-Token" => csrf_token }
  end

  # `browser:` is an integration session (self, or `open_session` to simulate ANOTHER browser with its own jar).
  def sign_in(user = nil, password: DEFAULT_PASSWORD, browser: self)
    user ||= create(:user, password:)
    browser.post "/api/v1/auth/login", params: { email: user.email, password: }, as: :json
    raise "sign_in falló: #{browser.response.status} #{browser.response.body}" unless browser.response.status == 200

    SignedIn.new(user:, csrf_token: browser.response.parsed_body.dig("data", "csrf_token"), session_token: browser.cookies[Api::SessionCookie.name])
  end
end

RSpec.configure { |config| config.include AuthenticationHelpers, type: :request }
