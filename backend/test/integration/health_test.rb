require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "GET /api/health responde 200 con status ok" do
    get "/api/health"

    assert_response :ok
    assert_equal({ "status" => "ok" }, response.parsed_body)
  end

  test "GET /api/health no consulta la base de datos" do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    get "/api/health"

    assert_empty queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "las rutas viven bajo /api (sin prefijo no existen)" do
    get "/health"

    assert_response :not_found
  end
end
