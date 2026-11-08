require "test_helper"

class ReadyTest < ActionDispatch::IntegrationTest
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
    broken = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "db caída" }
    original = ActiveRecord::Base.method(:with_connection)
    ActiveRecord::Base.define_singleton_method(:with_connection, &broken)

    begin
      get "/api/ready"
    ensure
      ActiveRecord::Base.define_singleton_method(:with_connection, original)
    end

    assert_response :service_unavailable
    assert_equal "unavailable", response.parsed_body.dig("checks", "database")
    assert_equal "ok", response.parsed_body.dig("checks", "redis")
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
end
