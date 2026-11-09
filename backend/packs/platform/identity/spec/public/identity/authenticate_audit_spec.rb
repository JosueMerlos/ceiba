require "rails_helper"

# Identity::Authenticate y CurrentSession registran en la auditoría con los datos que reciben (sin depender de la request).
RSpec.describe "Identity: auditoría desde los servicios" do
  let!(:user) { create(:user, email: "ana@ceiba.test", password: "contraseña-segura-1") }

  it "un login fallido llamado como servicio registra ip y user agent recibidos" do
    expect do
      Identity::Authenticate.call(email: "x@ceiba.test", password: "mal", ip: "198.51.100.4", user_agent: "curl/8")
    end.to raise_error(Identity::InvalidCredentials)

    expect(Audit::AuthEvent.last).to have_attributes(action: "auth.login_failed", ip: IPAddr.new("198.51.100.4"), user_agent: "curl/8")
  end

  it "el login correcto y la emisión de la sesión son atómicos: si falla la auditoría no queda sesión" do
    allow(Audit).to receive(:record_auth).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect do
      Identity::Authenticate.call(email: user.email, password: "contraseña-segura-1")
    end.to raise_error(ActiveRecord::StatementInvalid)

    expect(Identity::Session.where(user_id: user.id)).to be_empty
  end
end
