require "rails_helper"

RSpec.describe Identity::CurrentSession do
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-11-08 12:00:00") }
  let(:session) { Identity::Session.issue!(user:, now:) }

  describe ".resolve" do
    it "devuelve la sesión actual con su principal" do
      current = described_class.resolve(session.token, now:)

      expect(current.principal).to eq(Identity::Principal::User.new(id: user.id, email: user.email, full_name: user.full_name))
      expect(current.expires_at).to eq(now + 7.days)
    end

    it "devuelve nil para token ausente, desconocido, revocado o vencido" do
      expect(described_class.resolve(nil, now:)).to be_nil
      expect(described_class.resolve("desconocido", now:)).to be_nil
      session.revoke!(now:)
      expect(described_class.resolve(session.token, now:)).to be_nil
    end

    it "vence a las 12 h sin actividad" do
      expect(described_class.resolve(session.token, now: now + 12.hours)).to be_nil
    end

    it "registra la actividad con throttle de 1 minuto" do
      described_class.resolve(session.token, now: now + 30.seconds)
      expect(session.reload.last_seen_at).to eq(now)

      described_class.resolve(session.token, now: now + 90.seconds)
      expect(session.reload.last_seen_at).to eq(now + 90.seconds)
    end
  end

  describe "#csrf_token" do
    it "es estable para la sesión y distinto entre sesiones" do
      other = Identity::Session.issue!(user:, now:)

      first = described_class.resolve(session.token, now:).csrf_token
      expect(described_class.resolve(session.token, now:).csrf_token).to eq(first)
      expect(described_class.resolve(other.token, now:).csrf_token).not_to eq(first)
    end

    it "no contiene el token de la sesión ni su digest" do
      csrf = described_class.resolve(session.token, now:).csrf_token

      expect(csrf).not_to include(session.token)
      expect(csrf).not_to include(session.token_digest)
    end

    it "se valida en tiempo constante: acepta el propio y rechaza nulo, vacío, ajeno o truncado", :aggregate_failures do
      current = described_class.resolve(session.token, now:)
      other = described_class.resolve(Identity::Session.issue!(user:, now:).token, now:)

      expect(current.valid_csrf_token?(current.csrf_token)).to be(true)
      expect(current.valid_csrf_token?(nil)).to be(false)
      expect(current.valid_csrf_token?("")).to be(false)
      expect(current.valid_csrf_token?(other.csrf_token)).to be(false)
      expect(current.valid_csrf_token?(current.csrf_token[0..-2])).to be(false)
    end
  end

  describe "#revoke! y #revoke_all!" do
    it "revoca solo esta sesión" do
      other = Identity::Session.issue!(user:, now:)

      described_class.resolve(session.token, now:).revoke!(now:)

      expect(described_class.resolve(session.token, now:)).to be_nil
      expect(described_class.resolve(other.token, now:)).to be_present
    end

    it "revoca todas las del usuario" do
      other = Identity::Session.issue!(user:, now:)

      described_class.resolve(session.token, now:).revoke_all!(now:)

      expect(described_class.resolve(session.token, now:)).to be_nil
      expect(described_class.resolve(other.token, now:)).to be_nil
    end
  end
end
