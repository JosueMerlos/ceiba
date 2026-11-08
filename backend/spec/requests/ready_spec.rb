require "rails_helper"

RSpec.describe "GET /api/ready" do
  def with_redis_url(url)
    original = Rails.configuration.x.redis_url
    Rails.configuration.x.redis_url = url
    yield
  ensure
    Rails.configuration.x.redis_url = original
  end

  def with_database_config(config)
    original = Rails.configuration.x.readiness_database_config
    Rails.configuration.x.readiness_database_config = config
    yield
  ensure
    Rails.configuration.x.readiness_database_config = original
  end

  let(:database_config) { ActiveRecord::Base.connection_db_config.configuration_hash }

  it "responde 200 cuando PostgreSQL y Redis responden" do
    get "/api/ready"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "status" => "ok", "checks" => { "database" => "ok", "redis" => "ok" }
    )
  end

  it "responde 503 cuando Redis no responde" do
    with_redis_url("redis://127.0.0.1:1/0") { get "/api/ready" }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include(
      "status" => "unavailable", "checks" => { "database" => "ok", "redis" => "unavailable" }
    )
  end

  it "responde 503 cuando PostgreSQL no responde" do
    with_database_config(database_config.merge(host: "127.0.0.1", port: 1)) { get "/api/ready" }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["checks"]).to eq("database" => "unavailable", "redis" => "ok")
  end

  it "responde 503 rápido cuando PostgreSQL acepta la conexión pero nunca responde" do
    with_blackhole do |port|
      with_database_config(database_config.merge(host: "127.0.0.1", port:)) do
        expect(elapsed_seconds { get "/api/ready" }).to be < 3
      end
    end

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig("checks", "database")).to eq("unavailable")
  end

  it "responde 503 rápido cuando Redis acepta la conexión pero nunca responde" do
    with_blackhole do |port|
      with_redis_url("redis://127.0.0.1:#{port}/0") do
        expect(elapsed_seconds { get "/api/ready" }).to be < 3
      end
    end

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig("checks", "redis")).to eq("unavailable")
  end

  it "no usa el pool de Active Record" do
    pool = spy_on_connection_pool

    get "/api/ready"

    expect(response).to have_http_status(:ok)
    expect_connection_pool_untouched(pool)
  end

  it "no filtra detalles internos de los errores" do
    with_redis_url("redis://127.0.0.1:1/0") { get "/api/ready" }

    expect(response.body).not_to match(/127\.0\.0\.1|ECONNREFUSED|Connection/i)
  end
end
