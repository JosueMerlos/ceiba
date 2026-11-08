require "rails_helper"

RSpec.describe "GET /api/health" do
  it "responde 200 con status ok" do
    get "/api/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => "ok")
  end

  it "no consulta la base de datos" do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    get "/api/health"

    expect(queries).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "solo existe bajo /api (sin prefijo no hay ruta)" do
    get "/health"

    expect(response).to have_http_status(:not_found)
  end
end
