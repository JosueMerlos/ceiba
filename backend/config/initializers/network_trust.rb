# Proxies de confianza y hosts permitidos (M0.13, config/middleware/network_trust.rb).
require Rails.root.join("config/middleware/network_trust").to_s

trusted_proxies = NetworkTrust::Proxies.from(ENV["TRUSTED_PROXIES"])
Rails.application.config.action_dispatch.trusted_proxies = trusted_proxies
Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, NetworkTrust::UntrustedForwardingFilter, trusted_proxies

# config.hosts solo en producción y staging: en desarrollo Rails ya acepta localhost y el proxy llama a `api:3000` dentro de
# compose; en test el host es www.example.com. Los hosts salen de APP_ORIGINS (config/initializers/authentication.rb).
if Rails.env.production?
  hosts = NetworkTrust::Hosts.from_origins(Rails.configuration.x.auth.allowed_origins)
  if hosts.any?
    Rails.application.config.hosts = hosts
    Rails.application.config.host_authorization = { exclude: NetworkTrust::Hosts::EXCLUDE }
  end
end
