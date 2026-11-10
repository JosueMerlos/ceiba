# Who we trust on the network: proxies that report the client IP, and allowed Hosts.
module NetworkTrust
  # `remote_ip` comes from X-Forwarded-For ONLY if the connection arrives from a trusted proxy. Rails already trusts loopback
  # and private ranges (10/8, 172.16/12, 192.168/16, fc00::/7), covering compose's Caddy and kamal-proxy on the same host.
  # A public-IP proxy (managed load balancer) is added with TRUSTED_PROXIES="203.0.113.0/24,198.51.100.4". Without it all
  # traffic looks like it comes from the proxy IP and Rack::Attack limits lump every client together.
  # Requirement: the edge proxy must OVERWRITE X-Forwarded-For (Caddy does by default), not append to the client's.
  module Proxies
    module_function

    # replace_defaults (production): TRUSTED_PROXIES REPLACES the private ranges, narrowing trust to the real proxy's IP
    # (kamal-proxy). Without TRUSTED_PROXIES Rails' defaults stay (the app never ends up with no proxy at all). In
    # development and test they are always ADDED (compose's Caddy IP changes with every network).
    def from(value, replace_defaults: false)
      extra = value.to_s.split(",").map(&:strip).compact_blank.map { |range| IPAddr.new(range) }
      return ActionDispatch::RemoteIp::TRUSTED_PROXIES if extra.empty?

      replace_defaults ? extra : extra + ActionDispatch::RemoteIp::TRUSTED_PROXIES
    end
  end

  # Rails trusts forwarding headers even when the connection does NOT come from a trusted proxy: anyone reaching the app
  # directly could forge their IP and dodge Rack::Attack's per-IP limit. This middleware, before RemoteIp:
  #   - ALWAYS drops `Forwarded` (RFC 7239), `Client-IP` and `X-Real-IP`: the app only reads `X-Forwarded-For`, which the
  #     proxy overwrites; other headers (a client can send them and the proxy forwards them) only serve to forge the IP,
  #     or to trigger IpSpoofAttackError (500) when `Client-IP` does not match;
  #   - drops `X-Forwarded-For` when the direct peer is not a trusted proxy.
  class UntrustedForwardingFilter
    ALWAYS_DROPPED = %w[HTTP_FORWARDED HTTP_CLIENT_IP HTTP_X_REAL_IP].freeze
    PROXY_ONLY = %w[HTTP_X_FORWARDED_FOR].freeze

    def initialize(app, proxies)
      @app = app
      @proxies = proxies
    end

    def call(env)
      ALWAYS_DROPPED.each { |header| env.delete(header) }
      PROXY_ONLY.each { |header| env.delete(header) } unless trusted_peer?(env["REMOTE_ADDR"])
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

  # Rejects unknown Hosts (config.hosts); hosts come from APP_ORIGINS, the same list that validates Origin. Probes are
  # excluded: a healthcheck calls by internal IP and arbitrary Host.
  module Hosts
    EXCLUDE = ->(request) { %w[/api/health /api/ready].include?(request.path) }

    module_function

    def from_origins(origins)
      origins.map { |origin| URI.parse(origin).then { |uri| uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}" } }
    end
  end
end
