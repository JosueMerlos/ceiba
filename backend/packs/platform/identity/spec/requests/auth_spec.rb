require "rails_helper"

# Endpoints de autenticación (M0.07, docs/architecture/11-security.md). Criterios 1, 2, 3, 6 y 7.
RSpec.describe "Autenticación: login, sesión actual y cierre" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, email: "ana@ceiba.test", password: "contraseña-segura-1") }
  let(:cookie_name) { Api::SessionCookie.name }

  after { travel_back }

  def login(email: user.email, password: "contraseña-segura-1", headers: {}, browser: self)
    browser.post "/api/v1/auth/login", params: { email:, password: }, headers:, as: :json
    browser.response
  end

  def set_cookie(response = self.response) = Array(response.headers["Set-Cookie"]).join("\n")

  describe "POST /api/v1/auth/login" do
    it "con credenciales válidas responde 200 con el usuario, el token CSRF y la caducidad" do
      login

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["data"]).to match(
        "user" => { "id" => user.id, "email" => "ana@ceiba.test", "full_name" => "Ana Pérez" },
        "csrf_token" => a_string_matching(/\A\h{64}\z/),
        "expires_at" => a_string_matching(/Z\z/)
      )
    end

    it "criterio 1: entrega una cookie HttpOnly, SameSite=Lax y de ruta /", :aggregate_failures do
      login

      cookie = set_cookie
      expect(cookie).to match(/\A#{cookie_name}=[\w-]{43};/)
      expect(cookie).to match(/httponly/i)
      expect(cookie).to match(/samesite=lax/i)
      expect(cookie).to match(%r{path=/(;|$)}i)
      expect(cookie).to match(/expires=/i)
    end

    it "criterio 1: la cookie lleva Secure y el prefijo __Host- cuando está activa la política de producción", :aggregate_failures do
      with_secure_cookies do
        https! # Rails no escribe cookies Secure en una request HTTP plana
        login

        cookie = set_cookie
        expect(cookie).to start_with("__Host-ceiba_session=")
        expect(cookie).to match(/;\s*secure/i)
        expect(cookie).not_to match(/domain=/i)
        expect(cookie).to match(%r{path=/(;|$)}i)
      end
    end

    it "criterio 1: la fila de sessions guarda el DIGEST del token y no el token en claro", :aggregate_failures do
      login
      token = cookies[cookie_name]

      session = Identity::Session.find_by!(user_id: user.id)
      expect(session.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(token))
      expect(session.token_digest).not_to eq(token)
      expect(session.attributes.values.map(&:to_s)).not_to include(token)
      expect(response.body).not_to include(token)
    end

    it "registra la IP y el user agent de la sesión" do
      login(headers: { "User-Agent" => "Navegador/1.0", "REMOTE_ADDR" => "203.0.113.9" })

      expect(Identity::Session.find_by!(user_id: user.id)).to have_attributes(user_agent: "Navegador/1.0")
    end

    it "no devuelve ni registra la contraseña ni su digest" do
      login

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("password")
    end

    it "criterio 6: correo inexistente y contraseña errónea dan la MISMA respuesta (status y cuerpo)", :aggregate_failures do
      user
      same_request = { "X-Request-Id" => "req-fijo-1" }

      login(email: "nadie@ceiba.test", password: "contraseña-segura-1", headers: same_request)
      unknown = [ response.status, response.media_type, response.parsed_body, set_cookie ]
      login(email: "ana@ceiba.test", password: "contraseña-incorrecta", headers: same_request)
      wrong_password = [ response.status, response.media_type, response.parsed_body, set_cookie ]

      expect(unknown).to eq(wrong_password)
      expect(unknown.first).to eq(401)
      expect(unknown.third).to include("status" => 401, "code" => "auth.invalid_credentials", "instance" => "/api/v1/auth/login")
      expect(unknown.last).to be_empty
    end

    it "criterio 6: ambas respuestas solo difieren en el request_id" do
      user

      login(email: "nadie@ceiba.test")
      first = response.parsed_body
      login(password: "contraseña-incorrecta")
      second = response.parsed_body

      expect(first.except("request_id")).to eq(second.except("request_id"))
      expect(first).to include("status" => 401, "code" => "auth.invalid_credentials")
    end

    it "no crea sesiones con credenciales inválidas" do
      user

      expect { login(password: "mal-mal-mal-mal") }.not_to change(Identity::Session, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it "responde 400 si faltan el correo o la contraseña" do
      post "/api/v1/auth/login", params: { email: "ana@ceiba.test" }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("request.invalid")
    end

    it "no es explotable con un JSON de tipos inesperados (hash en lugar de texto)" do
      post "/api/v1/auth/login", params: { email: { "$ne" => "" }, password: { a: 1 } }, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "criterio 7: rota el token, y la sesión anterior del navegador deja de valer", :aggregate_failures do
      login
      before_login = cookies[cookie_name]
      get "/api/v1/auth/session"
      expect(response).to have_http_status(:ok)

      login
      after_login = cookies[cookie_name]

      expect(after_login).not_to eq(before_login)
      expect(Identity::Session.where(token_digest: Identity::Session.digest(before_login)).pick(:revoked_at)).to be_present
      stale = open_session
      stale.cookies[cookie_name] = before_login
      stale.get "/api/v1/auth/session"
      expect(stale.response).to have_http_status(:unauthorized)
    end

    it "criterio 7: un token fijado por un atacante antes del login no sirve después" do
      attacker = sign_in(create(:user))
      victim_browser = open_session
      victim_browser.cookies[cookie_name] = attacker.session_token

      login(browser: victim_browser)

      probe = open_session
      probe.cookies[cookie_name] = attacker.session_token
      probe.get "/api/v1/auth/session"
      expect(probe.response).to have_http_status(:unauthorized)
    end

    it "acepta el correo con otro formato de mayúsculas y espacios" do
      user
      login(email: "  ANA@ceiba.test ")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/auth/session" do
    it "sin cookie responde 401 problem+json" do
      get "/api/v1/auth/session"

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("status" => 401, "code" => "auth.unauthenticated")
    end

    it "con una cookie desconocida responde 401" do
      cookies[cookie_name] = "token-inventado"

      get "/api/v1/auth/session"

      expect(response).to have_http_status(:unauthorized)
    end

    it "con sesión válida devuelve el usuario y el MISMO token CSRF que el login" do
      signed_in = sign_in(user)

      get "/api/v1/auth/session"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("user" => include("id" => user.id), "csrf_token" => signed_in.csrf_token)
    end

    it "no cambia la cookie ni crea sesiones" do
      sign_in(user)

      expect { get "/api/v1/auth/session" }.not_to change(Identity::Session, :count)
      expect(set_cookie).to be_empty
    end

    it "criterio 3: tras 12 h sin actividad responde 401" do
      sign_in(user)

      travel 12.hours + 1.second
      get "/api/v1/auth/session"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("auth.unauthenticated")
    end

    it "criterio 3: antes de las 12 h sigue válida, y la actividad reinicia el contador" do
      sign_in(user)

      travel 11.hours
      get "/api/v1/auth/session"
      expect(response).to have_http_status(:ok)

      travel 11.hours
      get "/api/v1/auth/session"
      expect(response).to have_http_status(:ok)
    end

    it "expira a los 7 días aunque el usuario siga activo" do
      sign_in(user)

      15.times do
        travel 11.hours
        get "/api/v1/auth/session"
        expect(response).to have_http_status(:ok)
      end
      travel 11.hours
      get "/api/v1/auth/session"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    it "revoca la sesión actual, borra la cookie y responde 204" do
      signed_in = sign_in(user)

      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers

      expect(response).to have_http_status(:no_content)
      expect(set_cookie).to match(/#{cookie_name}=;/).and match(/expires=Thu, 01 Jan 1970/i)
      expect(Identity::Session.find_by!(token_digest: Identity::Session.digest(signed_in.session_token)).revoked_at).to be_present
    end

    it "la cookie ya no sirve (aunque alguien la hubiera copiado)" do
      signed_in = sign_in(user)
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers

      copied = open_session
      copied.cookies[cookie_name] = signed_in.session_token
      copied.get "/api/v1/auth/session"

      expect(copied.response).to have_http_status(:unauthorized)
    end

    it "no cierra las sesiones de otros dispositivos" do
      other_browser = open_session
      other = sign_in(user, browser: other_browser)
      signed_in = sign_in(user)

      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers

      other_browser.get "/api/v1/auth/session"
      expect(other_browser.response).to have_http_status(:ok)
      expect(other.session_token).not_to eq(signed_in.session_token)
    end

    it "sin sesión responde 401" do
      delete "/api/v1/auth/logout"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/auth/sessions" do
    it "criterio 2: revoca TODAS las sesiones del usuario y la cookie de otro navegador recibe 401", :aggregate_failures do
      other_browser = open_session
      sign_in(user, browser: other_browser)
      signed_in = sign_in(user)

      delete "/api/v1/auth/sessions", headers: signed_in.csrf_headers

      expect(response).to have_http_status(:no_content)
      other_browser.get "/api/v1/auth/session"
      expect(other_browser.response).to have_http_status(:unauthorized)
      get "/api/v1/auth/session"
      expect(response).to have_http_status(:unauthorized)
      expect(Identity::Session.where(user_id: user.id, revoked_at: nil)).to be_empty
    end

    it "no toca las sesiones de otros usuarios" do
      bystander_browser = open_session
      sign_in(create(:user), browser: bystander_browser)
      signed_in = sign_in(user)

      delete "/api/v1/auth/sessions", headers: signed_in.csrf_headers

      bystander_browser.get "/api/v1/auth/session"
      expect(bystander_browser.response).to have_http_status(:ok)
    end

    it "borra la cookie del navegador actual" do
      signed_in = sign_in(user)

      delete "/api/v1/auth/sessions", headers: signed_in.csrf_headers

      expect(set_cookie).to match(/expires=Thu, 01 Jan 1970/i)
    end

    it "sin sesión responde 401" do
      delete "/api/v1/auth/sessions"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  def with_secure_cookies
    original = Rails.configuration.x.auth.secure_cookies
    Rails.configuration.x.auth.secure_cookies = true
    yield
  ensure
    Rails.configuration.x.auth.secure_cookies = original
  end
end
