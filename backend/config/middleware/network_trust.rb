# De quién nos fiamos en la red (M0.13): proxies que informan la IP del cliente y Host permitidos.
module NetworkTrust
  # `remote_ip` sale de X-Forwarded-For SOLO si la conexión llega de un proxy de confianza. Rails ya confía en loopback y en los
  # rangos privados (10/8, 172.16/12, 192.168/16, fc00::/7): cubre el Caddy de compose y kamal-proxy en el mismo host. Un proxy
  # con IP pública (balanceador gestionado) se añade con TRUSTED_PROXIES="203.0.113.0/24,198.51.100.4". Sin esto, todo el
  # tráfico parece venir de la IP del proxy y los límites de Rack::Attack agrupan a todos los clientes en uno.
  # Condición: el proxy de borde debe SOBRESCRIBIR X-Forwarded-For (Caddy lo hace por defecto), no concatenar el del cliente.
  module Proxies
    module_function

    def from(value)
      extra = value.to_s.split(",").map(&:strip).compact_blank.map { |range| IPAddr.new(range) }
      extra + ActionDispatch::RemoteIp::TRUSTED_PROXIES
    end
  end

  # Rails confía en X-Forwarded-For aunque la conexión NO venga de un proxy de confianza (probado en
  # spec/requests/remote_ip_spec.rb): quien llegue directo a la app podría falsear su IP y esquivar el límite por IP de
  # Rack::Attack. Este middleware, antes de RemoteIp, descarta las cabeceras de reenvío cuando el par directo no es un proxy
  # de confianza.
  class UntrustedForwardingFilter
    FORWARDING_HEADERS = %w[HTTP_X_FORWARDED_FOR HTTP_CLIENT_IP].freeze

    def initialize(app, proxies)
      @app = app
      @proxies = proxies
    end

    def call(env)
      FORWARDING_HEADERS.each { |header| env.delete(header) } unless trusted_peer?(env["REMOTE_ADDR"])
      @app.call(env)
    end

    private

    def trusted_peer?(address)
      ip = IPAddr.new(address.to_s)
      @proxies.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  # Rechazo de Host desconocidos (config.hosts): los hosts salen de APP_ORIGINS, la misma lista que valida Origin. Las sondas se
  # excluyen: un healthcheck llama por IP interna y Host arbitrario.
  module Hosts
    EXCLUDE = ->(request) { %w[/api/health /api/ready].include?(request.path) }

    module_function

    def from_origins(origins)
      origins.map { |origin| URI.parse(origin).then { |uri| uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}" } }
    end
  end
end
