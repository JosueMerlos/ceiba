# Layer-1 rate limiting: Rack::Attack BEFORE authentication and without touching the database. It only uses keys available
# without a session: the real IP, and the email in the login body.
#
# This file holds the logic (limits, keys, 429 responses) so it can be tested; the rules are registered in
# config/initializers/throttling.rb. Not autoloaded (initializers cannot see app/); Api::Problem is resolved when responding.
require "digest"
require "json"

module RateLimiting
  LOGIN_PATH = %r{\A/api/v1/auth/login(\.\w+)?\z} # with or without a format extension: Rails would accept it too
  # The public availability route, with the slug captured as any non-slash segment: whether it is a valid slug is the endpoint's
  # call (a 404), not this layer's. Compared on the DECODED, slash-squeezed path, ignoring case and surrounding whitespace, which is how the router will
  # resolve it: a variant must not slip past with a counter of its own while still reaching the endpoint.
  PUBLIC_AVAILABILITY_PATH = %r{\A/api/public/v1/c/([^/]+)/availability/?\z}i
  PROBE_PATHS = %w[/api/health /api/ready].freeze
  MAX_LOGIN_BODY_BYTES = 4096

  # limit: requests per window; period: window seconds; ban: block seconds (only the nonexistent-route rule).
  RULES = {
    catch_all: { limit: 600, period: 5.minutes.to_i },
    login_ip: { limit: 5, period: 15.minutes.to_i },
    login_email: { limit: 10, period: 15.minutes.to_i },
    public_availability: { limit: 60, period: 1.minute.to_i },
    not_found: { limit: 10, period: 5.minutes.to_i, ban: 1.hour.to_i }
  }.freeze
  # Relaxed in development (a developer mistypes the password more than 5 times); test is not limited.
  DEVELOPMENT_LIMITS = { catch_all: 100_000, login_ip: 1000, login_email: 1000, public_availability: 100_000, not_found: 100_000 }.freeze

  module_function

  # RATE_LIMIT_<RULE> (e.g. RATE_LIMIT_LOGIN_IP=20) changes the limit without a code deploy.
  def limit(rule)
    configured = ENV["RATE_LIMIT_#{rule.to_s.upcase}"]
    return Integer(configured) if configured.present?

    Rails.env.development? ? DEVELOPMENT_LIMITS.fetch(rule) : RULES.fetch(rule).fetch(:limit)
  end

  def period(rule) = RULES.fetch(rule).fetch(:period)

  # The CLIENT IP as ActionDispatch::RemoteIp resolves it (trusted proxies), not Rack::Request#ip. If resolving it raises
  # IpSpoofAttackError (contradictory forwarding headers) the peer address is used: a 500 would be worse.
  def ip(request)
    (request.env["action_dispatch.remote_ip"] || request.ip).to_s
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    request.env["REMOTE_ADDR"].to_s
  end

  # IPv4 as is; IPv6 grouped by /64 (a client gets at least a /64, and rotating addresses inside it must not grant a new
  # limit each time).
  def client_key(request)
    address = IPAddr.new(ip(request))
    address.ipv6? && !address.ipv4_mapped? ? "#{address.mask(64)}/64" : address.to_s
  rescue IPAddr::InvalidAddressError
    ip(request)
  end

  def oversized_login?(request)
    login?(request) && (request.content_length.to_i > MAX_LOGIN_BODY_BYTES || request.get_header("HTTP_TRANSFER_ENCODING").present?)
  end

  def probe?(request) = PROBE_PATHS.include?(request.path)

  # The company slug of an anonymous availability request, normalized as Tenancy::PublicDirectory does (strip and downcase), or
  # nil for any other path. HEAD counts too: Rails routes it to the GET endpoint.
  def public_availability_slug(request)
    path = Rack::Utils.unescape_path(request.path).squeeze("/")
    PUBLIC_AVAILABILITY_PATH.match(path)&.captures&.first&.strip&.downcase if (request.get? || request.head?) && path.valid_encoding?
  rescue ArgumentError
    nil
  end

  def login?(request) = request.post? && LOGIN_PATH.match?(request.path)

  # Digest of the normalized email (as Identity::User does): the email is never stored in Redis. Only reads small JSON bodies.
  def login_email_digest(request)
    return unless login?(request) && request.media_type == "application/json"
    return unless request.content_length.to_i.between?(1, MAX_LOGIN_BODY_BYTES) # larger ones are rejected earlier (413)

    body = request.body.read(MAX_LOGIN_BODY_BYTES)
    request.body.rewind
    email = JSON.parse(body.to_s)["email"] if body.to_s.lstrip.start_with?("{")
    Digest::SHA256.hexdigest(email.strip.downcase) if email.is_a?(String) && email.present?
  rescue JSON::ParserError
    nil
  end

  def ban_key(request) = "ban:not-found:#{client_key(request)}"

  # The stored value is when the block ends; it is compared with the clock in addition to Redis' TTL.
  def banned?(request) = Rack::Attack.cache.read(ban_key(request)).to_i > Time.now.to_i

  def throttled_response(request)
    data = request.env["rack.attack.match_data"]
    retry_after = (data[:period] - (data[:epoch_time] % data[:period])).to_i
    respond(request, code: "rate_limit.exceeded", retry_after:, limit: data[:limit])
  end

  def blocklisted_response(request)
    return request_too_large(request) if request.env["rack.attack.matched"] == "login/oversized"

    blocked_response(request)
  end

  # A real login is a few dozen bytes. A larger body (padding to push the email out of what is read and dodge the per-email
  # limit) is rejected unparsed, and so is Transfer-Encoding (unknown length).
  def request_too_large(request)
    problem = Api::Problem.new(status: 413, code: "request.too_large", request: ActionDispatch::Request.new(request.env))
    body = problem.to_h.to_json
    [ 413, { "Content-Type" => "#{Api::Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s }, [ body ] ]
  end

  def blocked_response(request)
    until_epoch = Rack::Attack.cache.read(ban_key(request)).to_i
    retry_after = [ until_epoch - Time.now.to_i, 1 ].max
    respond(request, code: "rate_limit.blocked", retry_after:, limit: limit(:not_found))
  end

  def respond(request, code:, retry_after:, limit:)
    problem = Api::Problem.new(status: 429, code:, request: ActionDispatch::Request.new(request.env))
    body = problem.to_h.to_json
    headers = {
      "Content-Type" => "#{Api::Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s,
      "Retry-After" => retry_after.to_s, "RateLimit-Limit" => limit.to_s, "RateLimit-Remaining" => "0", "RateLimit-Reset" => retry_after.to_s
    }
    [ 429, headers, [ body ] ]
  end

  # Counts per IP the responses for a NONEXISTENT ROUTE (ActionController::RoutingError, or unknown HTTP method) and writes
  # the block at the limit. Business 404s (invisible resource, inconsistent context) are NOT counted: a legitimate user
  # causes them and a whole clinic shares one IP. Sits just INSIDE Rack::Attack (it needs the app's response, which a
  # blocklist cannot see): the blocklist reads the mark written here. Rails leaves the exception in
  # `action_dispatch.exception` when delegating to the exceptions app; 404s a controller rescues do not leave it.
  class NotFoundTracker
    def initialize(app) = @app = app

    def call(env)
      response = @app.call(env)
      record(env) if Rack::Attack.enabled && [ 404, 405 ].include?(response.first) && routing_failure?(env)
      response
    end

    private

    ROUTING_ERRORS = [ ActionController::RoutingError, ActionController::UnknownHttpMethod ].freeze

    def routing_failure?(env) = ROUTING_ERRORS.any? { |error| env["action_dispatch.exception"].is_a?(error) }

    def record(env)
      request = Rack::Attack::Request.new(env)
      count = Rack::Attack.cache.count("not-found:#{RateLimiting.client_key(request)}", RateLimiting.period(:not_found))
      return if count < RateLimiting.limit(:not_found)

      ban = RateLimiting::RULES.dig(:not_found, :ban)
      Rack::Attack.cache.write(RateLimiting.ban_key(request), Time.now.to_i + ban, ban)
    end
  end
end
