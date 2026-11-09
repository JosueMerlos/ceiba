require "rails_helper"

# Tarea 2 de M0.07: sesión en BD con token aleatorio guardado como DIGEST, expiración por inactividad (12 h) y absoluta
# (7 días), revocación (docs/architecture/11-security.md, "Sesiones del panel").
RSpec.describe Identity::Session do
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-11-08 12:00:00") }

  def issue(**attributes) = described_class.issue!(user:, ip: "203.0.113.7", user_agent: "RSpec", now:, **attributes)

  describe ".issue!" do
    it "genera un token aleatorio de 256 bits y guarda solo su digest SHA-256" do
      session = issue

      expect(session.token).to match(/\A[A-Za-z0-9_-]{43}\z/)
      expect(session.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(session.token))
      expect(described_class.column_names).not_to include("token")
      expect(session.reload.attributes.values.map(&:to_s)).not_to include(session.token)
    end

    it "no repite tokens" do
      expect(Array.new(5) { issue.token }.uniq.size).to eq(5)
    end

    it "fija inactividad, vigencia absoluta y metadatos" do
      session = issue

      expect(session).to have_attributes(user:, ip: IPAddr.new("203.0.113.7"), user_agent: "RSpec", last_seen_at: now, expires_at: now + 7.days, revoked_at: nil)
    end

    it "acota el user agent a 255 caracteres" do
      expect(issue(user_agent: "x" * 400).user_agent.length).to eq(255)
    end

    it "el token en claro no se puede leer de una sesión recargada" do
      expect(described_class.find(issue.id).token).to be_nil
    end
  end

  describe ".find_active_by_token" do
    it "encuentra la sesión por el digest del token" do
      session = issue

      expect(described_class.find_active_by_token(session.token, now:)).to eq(session)
    end

    it "no encuentra un token desconocido, vacío o nulo" do
      issue

      expect(described_class.find_active_by_token("otro-token", now:)).to be_nil
      expect(described_class.find_active_by_token("", now:)).to be_nil
      expect(described_class.find_active_by_token(nil, now:)).to be_nil
    end

    it "no acepta el propio digest como si fuera el token" do
      session = issue

      expect(described_class.find_active_by_token(session.token_digest, now:)).to be_nil
    end

    it "sigue activa justo antes de las 12 h sin actividad y deja de estarlo a las 12 h" do
      session = issue

      expect(described_class.find_active_by_token(session.token, now: now + 12.hours - 1.second)).to eq(session)
      expect(described_class.find_active_by_token(session.token, now: now + 12.hours)).to be_nil
    end

    it "expira a los 7 días aunque haya actividad reciente" do
      session = issue
      session.update!(last_seen_at: now + 7.days - 1.minute)

      expect(described_class.find_active_by_token(session.token, now: now + 7.days - 30.seconds)).to eq(session)
      expect(described_class.find_active_by_token(session.token, now: now + 7.days)).to be_nil
    end

    it "no devuelve una sesión revocada" do
      session = issue
      session.revoke!(now:)

      expect(described_class.find_active_by_token(session.token, now:)).to be_nil
    end
  end

  describe "#touch_activity!" do
    it "no escribe si la última actividad es de hace menos de 1 minuto (throttle)" do
      session = issue

      expect { session.touch_activity!(now: now + 59.seconds) }.not_to(change { session.reload.last_seen_at })
    end

    it "actualiza la última actividad pasado el minuto" do
      session = issue

      session.touch_activity!(now: now + 61.seconds)

      expect(session.reload.last_seen_at).to eq(now + 61.seconds)
    end

    it "extiende la inactividad pero nunca la vigencia absoluta" do
      session = issue

      session.touch_activity!(now: now + 5.hours)

      expect(session.reload.expires_at).to eq(now + 7.days)
    end
  end

  describe "#revoke! y .revoke_all_for" do
    it "marca revoked_at una sola vez" do
      session = issue
      session.revoke!(now:)
      session.revoke!(now: now + 1.hour)

      expect(session.reload.revoked_at).to eq(now)
    end

    it "revoca todas las sesiones activas del usuario y solo las suyas" do
      mine = [ issue, issue ]
      other = described_class.issue!(user: create(:user), now:)

      described_class.revoke_all_for(user, now:)

      expect(mine.map { |session| session.reload.revoked_at }).to all(eq(now))
      expect(other.reload.revoked_at).to be_nil
    end
  end

  it "el token_digest es único" do
    session = issue

    expect { described_class.create!(user:, token_digest: session.token_digest, last_seen_at: now, expires_at: now + 1.day) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "la sesión necesita usuario (FK)" do
    expect { described_class.create!(user_id: SecureRandom.uuid, token_digest: "x", last_seen_at: now, expires_at: now + 1.day) }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "es global: no es una tabla tenant" do
    expect(described_class.column_names).not_to include("organization_id")
    expect(Database::TenantTables.names).not_to include("sessions")
  end
end
