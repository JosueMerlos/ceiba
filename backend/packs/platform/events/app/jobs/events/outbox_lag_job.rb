module Events
  # Mide y reporta el lag del outbox (Events::OutboxLag). Job del sistema.
  class OutboxLagJob
    include Sidekiq::Job

    sidekiq_options queue: "default", tenant: false

    def perform = OutboxLag.report
  end
end
