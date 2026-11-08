require "test_helper"

class SidekiqTest < ActiveSupport::TestCase
  test "Active Job usa Sidekiq como adaptador (ADR-0009)" do
    assert_equal :sidekiq, Rails.application.config.active_job.queue_adapter
  end

  test "Sidekiq se conecta al Redis configurado" do
    assert_equal "PONG", Sidekiq.redis { |connection| connection.call("PING") }
  end
end
