require "test_helper"

class ReadyTest < ActionDispatch::IntegrationTest
  MAX_SECONDS = 3

  test "GET /api/ready responde 200 cuando PostgreSQL y Redis responden" do
    get "/api/ready"

    assert_response :ok
    assert_equal({ "status" => "ok", "checks" => { "database" => "ok", "redis" => "ok" } },
                 response.parsed_body)
  end

  test "GET /api/ready responde 503 cuando Redis no responde" do
    with_redis_url("redis://127.0.0.1:1/0") do
      get "/api/ready"
    end

    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body["status"]
    assert_equal "ok", response.parsed_body.dig("checks", "database")
    assert_equal "unavailable", response.parsed_body.dig("checks", "redis")
  end

  test "GET /api/ready responde 503 cuando PostgreSQL no responde" do
    with_database_config(unreachable_database_config) do
      get "/api/ready"
    end

    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body.dig("checks", "database")
    assert_equal "ok", response.parsed_body.dig("checks", "redis")
  end

  test "GET /api/ready responde 503 rápido cuando PostgreSQL acepta la conexión pero nunca responde" do
    with_blackhole do |port|
      with_database_config(database_config.merge(host: "127.0.0.1", port: port)) do
        elapsed = measure { get "/api/ready" }

        assert_operator elapsed, :<, MAX_SECONDS
      end
    end

    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body.dig("checks", "database")
  end

  test "GET /api/ready responde 503 rápido cuando Redis acepta la conexión pero nunca responde" do
    with_blackhole do |port|
      with_redis_url("redis://127.0.0.1:#{port}/0") do
        elapsed = measure { get "/api/ready" }

        assert_operator elapsed, :<, MAX_SECONDS
      end
    end

    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body.dig("checks", "redis")
  end

  test "la comprobación de PostgreSQL no usa ni ensucia el pool de Active Record" do
    before = ActiveRecord::Base.connection_pool.stat

    get "/api/ready"

    assert_equal before[:busy], ActiveRecord::Base.connection_pool.stat[:busy]
  end

  test "GET /api/ready no filtra detalles internos de los errores" do
    with_redis_url("redis://127.0.0.1:1/0") do
      get "/api/ready"
    end

    assert_no_match(/127\.0\.0\.1|ECONNREFUSED|Connection/i, response.body)
  end

  private

  def with_redis_url(url)
    original = Rails.configuration.x.redis_url
    Rails.configuration.x.redis_url = url
    yield
  ensure
    Rails.configuration.x.redis_url = original
  end

  def database_config
    ActiveRecord::Base.connection_db_config.configuration_hash
  end

  def unreachable_database_config
    database_config.merge(host: "127.0.0.1", port: 1)
  end

  def with_database_config(config)
    original = Rails.configuration.x.readiness_database_config
    Rails.configuration.x.readiness_database_config = config
    yield
  ensure
    Rails.configuration.x.readiness_database_config = original
  end

  def measure
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end
