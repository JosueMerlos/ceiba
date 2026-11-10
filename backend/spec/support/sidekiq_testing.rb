# Sidekiq in "fake" mode by default: enqueued jobs accumulate in memory (Sidekiq::Queues) and do not touch Redis.
# Integration specs with real Redis (concurrent relay, Redis down) tag the group `:redis` and run with Sidekiq::Testing
# disabled (Sidekiq 8's new API: Sidekiq.testing!, no `require "sidekiq/testing"`).
require "sidekiq/api"

Sidekiq.testing!(:fake)

RSpec.configure do |config|
  config.before { Sidekiq::Job.clear_all }

  config.around(:each, :redis) do |example|
    Sidekiq.testing!(:disable)
    # Never clean a database other than the test-only one (/15): 0 is the development one.
    raise "Redis de test mal configurado: #{Sidekiq.redis { |c| c.call('CLIENT', 'INFO') }}" unless Sidekiq.redis { |c| c.call("CLIENT", "INFO") }.include?("db=15")

    Sidekiq.redis(&:flushdb)
    example.run
  ensure
    Sidekiq.testing!(:fake)
  end
end

# `drain`/`perform_one` run test jobs through Sidekiq::Testing's server middleware chain: the same tenant middleware as
# in production is added (packs/platform/tenancy/config/initializers/sidekiq_tenant.rb).
Sidekiq::Testing.server_middleware { |chain| chain.add TenantJobMiddleware::Server }
