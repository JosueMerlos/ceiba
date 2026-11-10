require "rails_helper"

# Panel CSRF: token bound to the session in `X-CSRF-Token` + Origin/Referer validation on every mutation. A mutation
# with a valid session and no token -> 403.
RSpec.describe "CSRF y validación de Origin" do
  let(:user) { create(:user) }
  let!(:signed_in) { sign_in(user) }
  let(:own_origin) { "http://www.example.com" }

  def session_revoked?
    Identity::Session.find_by!(token_digest: Identity::Session.digest(signed_in.session_token)).revoked_at.present?
  end

  describe "token" do
    it "criterio 5: una mutación con sesión válida pero SIN token responde 403 problem+json y no se ejecuta", :aggregate_failures do
      delete "/api/v1/auth/logout"

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("status" => 403, "code" => "auth.csrf_invalid")
      expect(session_revoked?).to be(false)
    end

    it "con un token incorrecto responde 403" do
      delete "/api/v1/auth/logout", headers: { "X-CSRF-Token" => "0" * 64 }

      expect(response).to have_http_status(:forbidden)
    end

    it "con un token vacío responde 403" do
      delete "/api/v1/auth/logout", headers: { "X-CSRF-Token" => "" }

      expect(response).to have_http_status(:forbidden)
    end

    it "con el token de OTRA sesión responde 403" do
      other = sign_in(create(:user), browser: open_session)

      delete "/api/v1/auth/logout", headers: other.csrf_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "tras un nuevo login, el token anterior deja de valer (rota con la sesión)" do
      previous = signed_in.csrf_token
      fresh = sign_in(user)

      delete "/api/v1/auth/logout", headers: { "X-CSRF-Token" => previous }
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/auth/logout", headers: fresh.csrf_headers
      expect(response).to have_http_status(:no_content)
    end

    it "con el token correcto la mutación se ejecuta" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers

      expect(response).to have_http_status(:no_content)
      expect(session_revoked?).to be(true)
    end

    it "DELETE /auth/sessions también lo exige" do
      delete "/api/v1/auth/sessions"

      expect(response).to have_http_status(:forbidden)
      expect(Identity::Session.where(user_id: user.id, revoked_at: nil)).to exist
    end

    it "las lecturas (GET) no lo exigen" do
      get "/api/v1/auth/session"

      expect(response).to have_http_status(:ok)
    end

    it "el token no viaja en la cookie ni en una cabecera de la respuesta de lecturas" do
      get "/api/v1/auth/session"

      expect(response.headers.to_h.values.join).not_to include(signed_in.csrf_token)
    end

    it "sin sesión, una mutación responde 401 (autenticar va antes que el token)" do
      reset!

      delete "/api/v1/auth/logout"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Origin y Referer" do
    it "con un Origin ajeno responde 403 aunque el token sea correcto", :aggregate_failures do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "https://evil.example")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("auth.origin_forbidden")
      expect(session_revoked?).to be(false)
    end

    it "con Origin: null (iframe sandbox, redirecciones entre sitios) responde 403" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "null")

      expect(response).to have_http_status(:forbidden)
    end

    it "con el mismo host pero otro esquema o puerto responde 403" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "https://www.example.com")
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "http://www.example.com:3000")
      expect(response).to have_http_status(:forbidden)
    end

    it "con un host que solo CONTIENE el propio responde 403" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "http://www.example.com.evil.example")

      expect(response).to have_http_status(:forbidden)
    end

    it "con el Origin propio la mutación se ejecuta" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => own_origin)

      expect(response).to have_http_status(:no_content)
    end

    it "sin Origin pero con un Referer ajeno responde 403" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Referer" => "https://evil.example/pagina")

      expect(response).to have_http_status(:forbidden)
    end

    it "sin Origin y con un Referer propio la mutación se ejecuta" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Referer" => "#{own_origin}/panel/ajustes")

      expect(response).to have_http_status(:no_content)
    end

    it "con un Referer ilegible responde 403" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Referer" => "ht!tp://%%%")

      expect(response).to have_http_status(:forbidden)
    end

    it "el Origin manda sobre el Referer" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "https://evil.example", "Referer" => own_origin)

      expect(response).to have_http_status(:forbidden)
    end

    it "no se fía de Host ni X-Forwarded-Host: con la cabecera falsificada y un Origin que la coincide responde 403", :aggregate_failures do
      headers = signed_in.csrf_headers.merge("X-Forwarded-Host" => "evil.test", "Origin" => "http://evil.test")

      delete "/api/v1/auth/logout", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("auth.origin_forbidden")
      expect(session_revoked?).to be(false)
    end

    it "tampoco con un Host falsificado y un Referer que lo coincide" do
      headers = signed_in.csrf_headers.merge("X-Forwarded-Host" => "evil.test", "Referer" => "http://evil.test/x")

      delete "/api/v1/auth/logout", headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it "acepta los orígenes configurados explícitamente (config.x.auth.allowed_origins), sin importar el Host" do
      with_allowed_origins([ "https://panel.ceiba.test" ]) do
        delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => "https://panel.ceiba.test")
      end

      expect(response).to have_http_status(:no_content)
    end

    it "con los orígenes configurados deja de aceptar el que solo coincide con el Host" do
      with_allowed_origins([ "https://panel.ceiba.test" ]) do
        delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => own_origin)
      end

      expect(response).to have_http_status(:forbidden)
    end

    it "sin orígenes configurados (producción mal configurada) falla cerrado: ningún Origin pasa" do
      with_allowed_origins([]) do
        delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge("Origin" => own_origin)
      end

      expect(response).to have_http_status(:forbidden)
    end

    it "las lecturas no validan Origin" do
      get "/api/v1/auth/session", headers: { "Origin" => "https://evil.example" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "login" do
    before { reset! }

    it "con un Origin ajeno responde 403 y NO crea la sesión (login CSRF)", :aggregate_failures do
      expect do
        post "/api/v1/auth/login", params: { email: user.email, password: AuthenticationHelpers::DEFAULT_PASSWORD }, headers: { "Origin" => "https://evil.example" }, as: :json
      end.not_to change(Identity::Session, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("auth.origin_forbidden")
    end

    it "no exige token CSRF (todavía no hay sesión) y acepta el Origin propio" do
      post "/api/v1/auth/login", params: { email: user.email, password: AuthenticationHelpers::DEFAULT_PASSWORD }, headers: { "Origin" => own_origin }, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "no exige token aunque el navegador traiga una cookie de sesión anterior" do
      post "/api/v1/auth/login", params: { email: user.email, password: AuthenticationHelpers::DEFAULT_PASSWORD }, as: :json
      post "/api/v1/auth/login", params: { email: user.email, password: AuthenticationHelpers::DEFAULT_PASSWORD }, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "rutas públicas de las sondas de prueba" do
    include_context "con endpoints de prueba de la API"

    it "una mutación pública (sin sesión) con Origin ajeno también responde 403" do
      post "/api/v1/probes/create", params: { name: "x" }, headers: { "Origin" => "https://evil.example" }, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "una mutación pública sin Origin pasa (no hay sesión que proteger)" do
      post "/api/v1/probes/create", params: { name: "x" }, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  def with_allowed_origins(origins)
    original = Rails.configuration.x.auth.allowed_origins
    Rails.configuration.x.auth.allowed_origins = origins
    yield
  ensure
    Rails.configuration.x.auth.allowed_origins = original
  end
end
