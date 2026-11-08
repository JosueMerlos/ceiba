require "rails_helper"

RSpec.describe "Configuración de Sidekiq" do
  it "usa Sidekiq como adaptador de Active Job (ADR-0009)" do
    expect(Rails.application.config.active_job.queue_adapter).to eq(:sidekiq)
  end

  it "se conecta al Redis configurado" do
    expect(Sidekiq.redis { |connection| connection.call("PING") }).to eq("PONG")
  end
end
