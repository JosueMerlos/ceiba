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

  # Cabeceras con las que un cliente puede intentar decir "mi IP es otra": ninguna debe cambiar remote_ip.
  {
    "Forwarded (RFC 7239)" => { "HTTP_FORWARDED" => "for=6.6.6.6" },
    "X-Real-IP" => { "HTTP_X_REAL_IP" => "6.6.6.6" },
    "Client-IP" => { "HTTP_CLIENT_IP" => "6.6.6.6" }
  }.each do |name, header|
    it "#{name}: llegando DIRECTO (IP pública) no cambia la IP del cliente" do
      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => "198.51.100.7" }.merge(header)

      expect(logged_remote_ip).to eq("198.51.100.7")
    end

    it "#{name}: llegando por el proxy (par privado) tampoco: manda X-Forwarded-For del proxy, y no hay 500" do
      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => "172.18.0.5", "HTTP_X_FORWARDED_FOR" => "203.0.113.9" }.merge(header)

      expect(response).to have_http_status(:unauthorized)
      expect(logged_remote_ip).to eq("203.0.113.9")
    end
  end

  describe NetworkTrust::UntrustedForwardingFilter do
    let(:filter) { described_class.new(->(env) { env }, ActionDispatch::RemoteIp::TRUSTED_PROXIES) }
    let(:headers) { { "HTTP_FORWARDED" => "for=1", "HTTP_CLIENT_IP" => "1", "HTTP_X_REAL_IP" => "1", "HTTP_X_FORWARDED_FOR" => "1" } }

    it "borra SIEMPRE Forwarded, Client-IP y X-Real-IP, aunque el par sea de confianza; X-Forwarded-For se conserva" do
      env = filter.call({ "REMOTE_ADDR" => "172.18.0.5" }.merge(headers))

      expect(env.keys & %w[HTTP_FORWARDED HTTP_CLIENT_IP HTTP_X_REAL_IP]).to be_empty
      expect(env["HTTP_X_FORWARDED_FOR"]).to eq("1")
    end

    it "con un par que no es de confianza borra también X-Forwarded-For" do
      env = filter.call({ "REMOTE_ADDR" => "198.51.100.7" }.merge(headers))

      expect(env.keys & headers.keys).to be_empty
    end
  end

  describe NetworkTrust::Proxies do
    it "en producción TRUSTED_PROXIES SUSTITUYE los rangos privados (se estrecha a la IP del proxy real)" do
      proxies = described_class.from("10.0.0.7", replace_defaults: true)

      expect(proxies).to eq([ IPAddr.new("10.0.0.7") ])
    end

    it "sin TRUSTED_PROXIES, replace_defaults conserva los de Rails (no deja la app sin ningún proxy)" do
      expect(described_class.from(nil, replace_defaults: true)).to eq(ActionDispatch::RemoteIp::TRUSTED_PROXIES)
    end

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
