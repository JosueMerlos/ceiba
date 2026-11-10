require "rails_helper"

# Rate limiting layer 1: Rack::Attack before authentication and without touching the DB. Each rule runs with the clock
# frozen in a known window and the store reset.
RSpec.describe "Rate limiting (Rack::Attack)" do
  include_context "con endpoints de prueba de la API"
  include ActiveSupport::Testing::TimeHelpers

  # 12:00:01 UTC: 1 s into a 5 and 15 min window aligned with the epoch.
  let(:now) { Time.utc(2026, 11, 9, 12, 0, 1) }
  let(:ip) { "203.0.113.10" }

  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    travel_to(now) { example.run }
  ensure
    Rack::Attack.reset!
    Rack::Attack.enabled = false
  end

  def login(email: "ana@ceiba.test", from: ip)
    post "/api/v1/auth/login", params: { email:, password: "incorrecta" }, headers: { "REMOTE_ADDR" => from }, as: :json
  end

  def expect_rate_limited(retry_after:, limit:, code: "rate_limit.exceeded")
    expect(response).to have_http_status(:too_many_requests)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.headers).to include("Retry-After" => retry_after.to_s, "RateLimit-Limit" => limit.to_s, "RateLimit-Remaining" => "0", "RateLimit-Reset" => retry_after.to_s)
    expect(response.parsed_body).to include("status" => 429, "code" => code, "request_id" => response.headers["X-Request-Id"])
  end

  describe "regla 2: login por IP (5 / 15 min)" do
    it "criterio 2: el 6º intento desde una IP responde 429 con Retry-After y RateLimit-*" do
      5.times do
        login
        expect(response).to have_http_status(:unauthorized)
      end

      login

      expect_rate_limited(retry_after: 899, limit: 5)
    end

    it "la ruta con extensión de formato (/login.json) no esquiva la regla: cuenta igual" do
      5.times { login }

      post "/api/v1/auth/login.json", params: { email: "ana@ceiba.test", password: "x" }, headers: { "REMOTE_ADDR" => ip }, as: :json

      expect_rate_limited(retry_after: 899, limit: 5)
    end

    it "las rutas de la API no admiten extensión de formato (/login.json no existe)" do
      Rack::Attack.enabled = false

      post "/api/v1/auth/login.json", params: { email: "ana@ceiba.test", password: "x" }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "IPv6: las direcciones de un mismo /64 comparten límite (un cliente controla todo su /64)" do
      5.times { |n| login(from: "2001:db8:1:2::#{n + 1}") }

      login(from: "2001:db8:1:2:aaaa:bbbb:cccc:dddd")

      expect_rate_limited(retry_after: 899, limit: 5)
    end

    it "IPv6: otro /64 no se ve afectado" do
      6.times { |n| login(from: "2001:db8:1:2::#{n + 1}") }

      login(from: "2001:db8:1:3::1")

      expect(response).to have_http_status(:unauthorized)
    end

    it "otra IP no se ve afectada" do
      6.times { login }

      login(from: "203.0.113.11")

      expect(response).to have_http_status(:unauthorized)
    end

    it "la ventana siguiente vuelve a permitir intentos" do
      6.times { login }
      travel_to(now + 15.minutes)
      login

      expect(response).to have_http_status(:unauthorized)
    end

    it "el 429 también lleva las cabeceras de seguridad" do
      6.times { login }

      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end
  end

  describe "regla 3: login por correo normalizado (10 / 15 min)" do
    it "el 11º intento sobre el mismo correo responde 429 aunque cambie la IP, sin distinguir mayúsculas ni espacios" do
      emails = [ "ana@ceiba.test", " ANA@ceiba.test", "Ana@Ceiba.test " ]
      10.times { |n| login(email: emails[n % 3], from: "198.51.100.#{n + 1}") }
      expect(response).to have_http_status(:unauthorized)

      login(email: "ana@ceiba.test", from: "198.51.100.99")

      expect_rate_limited(retry_after: 899, limit: 10)
    end

    it "espacios o saltos de línea antes del JSON no esquivan la regla" do
      body = "  \n{\"email\":\"ana@ceiba.test\",\"password\":\"x\"}"
      10.times { |n| post "/api/v1/auth/login", params: body, headers: { "CONTENT_TYPE" => "application/json", "REMOTE_ADDR" => "198.51.100.#{n + 1}" } }

      post "/api/v1/auth/login", params: body, headers: { "CONTENT_TYPE" => "application/json", "REMOTE_ADDR" => "198.51.100.99" }

      expect_rate_limited(retry_after: 899, limit: 10)
    end

    it "un cuerpo de login de más de 4 KB (relleno para que no se lea el correo) se rechaza con 413 problem+json" do
      body = { email: "ana@ceiba.test", password: "x", relleno: "a" * 5000 }.to_json
      post "/api/v1/auth/login", params: body, headers: { "CONTENT_TYPE" => "application/json", "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:content_too_large)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("code" => "request.too_large")
    end

    it "otro correo no se ve afectado" do
      11.times { |n| login(from: "198.51.100.#{n + 1}") }

      login(email: "otra@ceiba.test", from: "198.51.100.200")

      expect(response).to have_http_status(:unauthorized)
    end

    it "un cuerpo que no es JSON válido no rompe la regla (lo rechaza la API como siempre)" do
      post "/api/v1/auth/login", params: "{no-json", headers: { "CONTENT_TYPE" => "application/json", "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:bad_request)
    end

    it "el correo no se guarda en claro en Redis (solo su huella)" do
      login
      keys = Rack::Attack.cache.store.redis.with { |redis| redis.keys("ratelimit:*") }

      expect(keys).not_to be_empty
      expect(keys.join).not_to include("ana@ceiba.test")
    end
  end

  describe "regla 1: catch-all por IP (600 / 5 min)" do
    it "la request 601 de una IP responde 429; las sondas de vida no cuentan" do
      600.times { get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip } }
      expect(response).to have_http_status(:unauthorized)
      get "/api/health", headers: { "REMOTE_ADDR" => ip }
      expect(response).to have_http_status(:ok)

      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect_rate_limited(retry_after: 299, limit: 600)
    end
  end

  describe "regla 8: 404/405 repetidos (10 / 5 min, bloqueo de 1 h)" do
    it "tras 10 respuestas 404 la IP queda bloqueada 1 h con 429 y Retry-After", :aggregate_failures do
      10.times do
        get "/api/v1/no-existe", headers: { "REMOTE_ADDR" => ip }
        expect(response).to have_http_status(:not_found)
      end

      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("3600")
      expect(response.parsed_body).to include("code" => "rate_limit.blocked")
    end

    it "los 405 cuentan igual" do
      10.times { delete "/api/health", headers: { "REMOTE_ADDR" => ip } }

      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "el bloqueo dura una hora: pasada, la IP vuelve a pasar; otra IP nunca se vio afectada" do
      10.times { get "/api/v1/no-existe", headers: { "REMOTE_ADDR" => ip } }
      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => "203.0.113.50" }
      expect(response).to have_http_status(:unauthorized)

      travel_to(now + 61.minutes)
      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:unauthorized)
    end

    it "los 404 de NEGOCIO (recurso no encontrado, contexto inconsistente) no cuentan: solo las rutas inexistentes" do
      12.times do
        get "/api/v1/probes/missing_record", headers: { "REMOTE_ADDR" => ip }
        expect(response).to have_http_status(:not_found)
      end
      get "/api/v1/probes/inconsistent_context", headers: { "REMOTE_ADDR" => ip }

      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:unauthorized)
    end

    it "los 404 del Access::RouteContextResolver real (empresa o sucursal fuera de alcance) tampoco cuentan" do
      Rack::Attack.enabled = false
      world = build_access_world
      manager = user_with_role("branch_manager", world, branch: world.branch_a1)
      sign_in(manager)
      Rack::Attack.enabled = true
      other_branch = "/api/v1/organizations/#{world.organization.id}/companies/#{world.company_a.id}/branches/#{world.branch_a2.id}"

      12.times do
        get other_branch, headers: { "REMOTE_ADDR" => ip }
        expect(response).to have_http_status(:not_found)
      end
      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:ok)
    end

    it "9 respuestas 404 no bloquean" do
      9.times { get "/api/v1/no-existe", headers: { "REMOTE_ADDR" => ip } }

      get "/api/v1/auth/session", headers: { "REMOTE_ADDR" => ip }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "IP del cliente ilegible" do
    it "si resolver la IP lanza IpSpoofAttackError se usa la dirección del par en lugar de fallar con 500" do
      env = Rack::MockRequest.env_for("/api/health", "REMOTE_ADDR" => "198.51.100.7")
      env["action_dispatch.remote_ip"] = Class.new { def to_s = raise(ActionDispatch::RemoteIp::IpSpoofAttackError, "spoof") }.new

      expect(RateLimiting.ip(Rack::Attack::Request.new(env))).to eq("198.51.100.7")
    end
  end

  describe "store y tolerancia a fallos" do
    it "usa Redis con el namespace ratelimit:" do
      login

      expect(Rack::Attack.cache.store.redis.with { |redis| redis.keys("ratelimit:rack::attack:*") }).not_to be_empty
    end

    it "si Redis no responde la API sigue funcionando (el límite falla abierto, no cierra el login)" do
      original = Rack::Attack.cache.store
      Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: "redis://127.0.0.1:1/15", namespace: "ratelimit", connect_timeout: 0.1)

      login

      expect(response).to have_http_status(:unauthorized)
    ensure
      Rack::Attack.cache.store = original
    end
  end

  describe "límites por variable de entorno" do
    it "RATE_LIMIT_LOGIN_IP sustituye el valor por defecto" do
      stub_const("ENV", ENV.to_h.merge("RATE_LIMIT_LOGIN_IP" => "2"))
      2.times { login }

      login

      expect_rate_limited(retry_after: 899, limit: 2)
    end
  end

  it "con Rack::Attack desactivado (valor por defecto en test) no limita" do
    Rack::Attack.enabled = false

    10.times { login }

    expect(response).to have_http_status(:unauthorized)
  end
end
