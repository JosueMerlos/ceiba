# Trusted proxies and allowed hosts.
require Rails.root.join("config/middleware/network_trust").to_s

trusted_proxies = NetworkTrust::Proxies.from(ENV["TRUSTED_PROXIES"], replace_defaults: Rails.env.production?)
Rails.application.config.action_dispatch.trusted_proxies = trusted_proxies
Rails.application.config.middleware.insert_before ActionDispatch::RemoteIp, NetworkTrust::UntrustedForwardingFilter, trusted_proxies

# config.hosts only in production and staging: in development Rails already accepts localhost and the proxy calls
# `api:3000` inside compose; in test the host is www.example.com. Hosts are derived from APP_ORIGINS.
if Rails.env.production?
  hosts = NetworkTrust::Hosts.from_origins(Rails.configuration.x.auth.allowed_origins)
  if hosts.any?
    Rails.application.config.hosts = hosts
    Rails.application.config.host_authorization = { exclude: NetworkTrust::Hosts::EXCLUDE }
  end
end
