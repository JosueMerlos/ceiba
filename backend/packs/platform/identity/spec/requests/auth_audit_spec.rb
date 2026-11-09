require "rails_helper"

# Eventos de autenticación en la auditoría (M0.11, criterios 1 y 2). Van a auth_audit_events (global): un login fallido con
# un correo sin cuenta no tiene organización. Peticiones HTTP reales, como las del navegador.
RSpec.describe "Auditoría de la autenticación" do
  let(:password) { "contraseña-segura-1" }
  let!(:user) { create(:user, email: "ana@ceiba.test", password:) }
  let(:headers) { { "User-Agent" => "Mozilla/5.0 (Prueba)", "REMOTE_ADDR" => "203.0.113.9" } }

  def events = Audit::AuthEvent.order(:id).to_a

  def login(email:, pass: password) = post("/api/v1/auth/login", params: { email:, password: pass }, as: :json, headers:)

  describe "login fallido (criterio 2)" do
    it "con un correo inexistente deja un evento con IP y user agent, sin usuario" do
      login(email: "nadie@ceiba.test", pass: "intento-secreto-99")

      expect(response).to have_http_status(:unauthorized)
      expect(events).to contain_exactly(
        have_attributes(action: "auth.login_failed", user_id: nil, ip: IPAddr.new("203.0.113.9"), user_agent: "Mozilla/5.0 (Prueba)")
      )
    end

    it "con contraseña errónea registra el usuario de la cuenta" do
      login(email: user.email, pass: "intento-secreto-99")

      expect(events).to contain_exactly(have_attributes(action: "auth.login_failed", user_id: user.id))
    end

    it "NO guarda la contraseña intentada, ni la real, ni el correo en claro" do
      login(email: "Nadie@Ceiba.test", pass: "intento-secreto-99")
      serialized = events.map { |event| event.attributes.to_json }.join

      expect(serialized).not_to include("intento-secreto-99")
      expect(serialized).not_to include(password)
      expect(serialized).not_to include("nadie@ceiba.test")
      expect(events.first.metadata).to eq("email_digest" => OpenSSL::Digest::SHA256.hexdigest("nadie@ceiba.test"))
    end

    it "el evento sobrevive al error 401 (se escribe aunque la petición falle)" do
      login(email: "nadie@ceiba.test")

      expect(Audit::AuthEvent.where(action: "auth.login_failed").count).to eq(1)
    end

    it "guarda el request_id de la petición (el mismo de X-Request-Id)" do
      login(email: "nadie@ceiba.test")

      expect(events.first.request_id).to eq(response.headers["X-Request-Id"])
    end

    it "un correo con otro formato de texto (hash en el JSON, 400) no deja evento de login" do
      post "/api/v1/auth/login", params: { email: { "$ne" => "x" }, password: }, as: :json, headers: headers

      expect(events).to be_empty
    end
  end

  describe "login correcto" do
    it "deja un evento con el usuario, IP y user agent, y el id de la sesión; sin token" do
      login(email: user.email)

      session = Identity::Session.find_by!(user_id: user.id)
      expect(events).to contain_exactly(
        have_attributes(action: "auth.login_succeeded", user_id: user.id, ip: IPAddr.new("203.0.113.9"), user_agent: "Mozilla/5.0 (Prueba)",
          metadata: { "session_id" => session.id })
      )
      expect(events.first.attributes.to_json).not_to include(response.cookies.values.first.to_s)
    end
  end

  describe "logout y revocación" do
    let!(:signed_in) { sign_in(user) }

    it "logout deja auth.logout con el usuario y la sesión" do
      delete "/api/v1/auth/logout", headers: signed_in.csrf_headers.merge(headers)

      expect(events.last).to have_attributes(action: "auth.logout", user_id: user.id, ip: IPAddr.new("203.0.113.9"))
      expect(events.last.metadata).to include("session_id" => Identity::Session.find_by!(user_id: user.id).id)
    end

    it "cerrar todas las sesiones deja auth.sessions_revoked con la cantidad revocada" do
      open_session_two = open_session
      sign_in(user, browser: open_session_two)

      delete "/api/v1/auth/sessions", headers: signed_in.csrf_headers.merge(headers)

      expect(events.last).to have_attributes(action: "auth.sessions_revoked", user_id: user.id, metadata: { "count" => 2 })
    end
  end

  it "la tabla de eventos de identidad rechaza modificaciones desde el modelo" do
    login(email: "nadie@ceiba.test")

    expect { events.first.update!(action: "otra") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
