require "rails_helper"
require Rails.root.join("config/middleware/network_trust").to_s

# Criterio 3 de M0.13 (parte automática): `remote_ip` es la del cliente, no la del proxy. La verificación real a través del
# Caddy de desarrollo está en las notas de cierre del hito.
RSpec.describe "IP real del cliente tras el proxy" do
  let(:output) { StringIO.new }

  around do |example|
    logger = ActiveSupport::Logger.new(output)
    logger.formatter = Observability::JsonLogFormatter.new
    original = Lograge.logger
    Lograge.logger = logger
    example.run
  ensure
    Lograge.logger = original
  end

  def logged_remote_ip = output.string.lines.filter_map { |line| JSON.parse(line)["remote_ip"] }.last

  it "una request que llega por el proxy de compose (red privada) usa X-Forwarded-For del proxy como IP del cliente" do
    get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => "172.18.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }

    expect(logged_remote_ip).to eq("203.0.113.9")
  end

  it "un cliente que llega DIRECTO (IP pública) no puede falsear su IP con X-Forwarded-For" do
    get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => "198.51.100.7", "HTTP_X_FORWARDED_FOR" => "1.2.3.4" }

    expect(logged_remote_ip).to eq("198.51.100.7")
  end

  describe NetworkTrust::Proxies do
    it "sin TRUSTED_PROXIES conserva los rangos privados y de loopback que Rails ya confía (red de compose, kamal-proxy)" do
      expect(described_class.from(nil)).to eq(ActionDispatch::RemoteIp::TRUSTED_PROXIES)
    end

    it "TRUSTED_PROXIES añade rangos (p. ej. un balanceador con IP pública) sin quitar los de Rails" do
      proxies = described_class.from("203.0.113.0/24, 198.51.100.4")

      expect(proxies).to include(IPAddr.new("203.0.113.0/24"), IPAddr.new("198.51.100.4"), IPAddr.new("172.16.0.0/12"))
      expect(proxies.any? { |range| range.include?("203.0.113.77") }).to be(true)
    end

    it "un rango inválido falla al arrancar (mejor que ignorarlo y agrupar todo el tráfico en la IP del proxy)" do
      expect { described_class.from("no-es-una-ip") }.to raise_error(IPAddr::InvalidAddressError)
    end
  end

  describe NetworkTrust::Hosts do
    it "deriva los hosts permitidos de APP_ORIGINS, con su puerto si lo tienen" do
      expect(described_class.from_origins([ "https://app.ceiba.example", "http://localhost:8080" ])).to eq([ "app.ceiba.example", "localhost:8080" ])
    end

    it "sin orígenes no restringe (APP_ORIGINS vacío ya hace fallar cerrado las mutaciones)" do
      expect(described_class.from_origins([])).to eq([])
    end

    it "las sondas de infraestructura se excluyen de la comprobación de Host (healthchecks por IP interna)" do
      exclusion = described_class::EXCLUDE

      expect(exclusion.call(Rack::Request.new(Rack::MockRequest.env_for("/api/health")))).to be(true)
      expect(exclusion.call(Rack::Request.new(Rack::MockRequest.env_for("/api/v1/auth/session")))).to be(false)
    end

    it "con hosts configurados, ActionDispatch::HostAuthorization rechaza un Host ajeno con 403" do
      app = ->(_env) { [ 200, {}, [ "ok" ] ] }
      guard = ActionDispatch::HostAuthorization.new(app, [ "app.ceiba.example" ], exclude: described_class::EXCLUDE)

      allowed = guard.call(Rack::MockRequest.env_for("/api/v1/auth/session", "HTTP_HOST" => "app.ceiba.example"))
      blocked = guard.call(Rack::MockRequest.env_for("/api/v1/auth/session", "HTTP_HOST" => "evil.test"))
      probe = guard.call(Rack::MockRequest.env_for("/api/health", "HTTP_HOST" => "10.0.0.5:3000"))

      expect([ allowed.first, blocked.first, probe.first ]).to eq([ 200, 403, 200 ])
    end
  end
end
