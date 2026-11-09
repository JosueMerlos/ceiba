require "rails_helper"

# Login (criterios 6 y 7 de M0.07): credenciales, rotación del token y tiempo constante frente a cuentas inexistentes.
RSpec.describe Identity::Authenticate do
  let!(:user) { create(:user, email: "ana@ceiba.test", password: "contraseña-segura-1") }
  let(:now) { Time.zone.parse("2026-11-08 12:00:00") }

  def call(email: "ana@ceiba.test", password: "contraseña-segura-1", **options)
    described_class.call(email:, password:, ip: "203.0.113.7", user_agent: "RSpec", now:, **options)
  end

  it "con credenciales válidas emite una sesión nueva y devuelve el token en claro UNA vez" do
    result = call

    expect(result.token).to be_present
    expect(result.current_session.principal).to eq(Identity::Principal::User.new(id: user.id, email: "ana@ceiba.test", full_name: "Ana Pérez"))
    expect(Identity::Session.find_by!(token_digest: Identity::Session.digest(result.token))).to have_attributes(user_id: user.id, ip: IPAddr.new("203.0.113.7"))
  end

  it "acepta el correo sin importar mayúsculas ni espacios" do
    expect(call(email: "  ANA@Ceiba.test ").current_session.principal.id).to eq(user.id)
  end

  it "con contraseña errónea lanza InvalidCredentials y no crea sesión" do
    expect { call(password: "contraseña-incorrecta") }.to raise_error(Identity::InvalidCredentials)
    expect(Identity::Session.count).to eq(0)
  end

  it "con correo inexistente lanza el MISMO error" do
    expect { call(email: "nadie@ceiba.test") }.to raise_error(Identity::InvalidCredentials)
  end

  it "con valores vacíos o nulos también lanza InvalidCredentials (sin ArgumentError de authenticate_by)" do
    expect { call(email: "", password: "") }.to raise_error(Identity::InvalidCredentials)
    expect { call(email: nil, password: nil) }.to raise_error(Identity::InvalidCredentials)
  end

  it "calcula bcrypt también cuando la cuenta no existe (iguala tiempos)" do
    allow(BCrypt::Engine).to receive(:hash_secret).and_call_original

    expect { call(email: "nadie@ceiba.test") }.to raise_error(Identity::InvalidCredentials)

    expect(BCrypt::Engine).to have_received(:hash_secret).at_least(:once)
  end

  it "calcula bcrypt cuando la cuenta existe y la contraseña es errónea" do
    allow(BCrypt::Engine).to receive(:hash_secret).and_call_original

    expect { call(password: "contraseña-incorrecta") }.to raise_error(Identity::InvalidCredentials)

    expect(BCrypt::Engine).to have_received(:hash_secret).at_least(:once)
  end

  describe "rotación (criterio 7)" do
    it "cada login emite un token distinto" do
      expect(call.token).not_to eq(call.token)
    end

    it "revoca la sesión anterior que presenta el navegador" do
      previous = call

      fresh = call(previous_token: previous.token)

      expect(fresh.token).not_to eq(previous.token)
      expect(Identity::CurrentSession.resolve(previous.token, now:)).to be_nil
      expect(Identity::CurrentSession.resolve(fresh.token, now:)).to be_present
    end

    it "revoca la sesión anterior aunque sea de OTRO usuario (no hay fijación de sesión)" do
      other = described_class.call(email: create(:user).email, password: "contraseña-segura-1", now:)

      call(previous_token: other.token)

      expect(Identity::CurrentSession.resolve(other.token, now:)).to be_nil
    end

    it "no toca las sesiones de otros dispositivos del mismo usuario" do
      elsewhere = call

      call

      expect(Identity::CurrentSession.resolve(elsewhere.token, now:)).to be_present
    end

    it "ignora un token anterior inválido" do
      expect { call(previous_token: "basura") }.not_to raise_error
    end

    it "con credenciales erróneas NO revoca la sesión anterior" do
      previous = call

      expect { call(password: "mal-mal-mal-mal", previous_token: previous.token) }.to raise_error(Identity::InvalidCredentials)

      expect(Identity::CurrentSession.resolve(previous.token, now:)).to be_present
    end
  end
end
