# The relay runs every 5 s, so the scheduler poll (30 s by default) must be shorter.
Sidekiq::Cron.configure { |cron| cron.cron_poll_interval = 1 }

# Scheduled jobs are registered when the Sidekiq process boots (not in web or console). Events::Schedule is resolved at
# that point, not during initialization (reloadable classes are not autoloaded in initializers).
Sidekiq.configure_server do |config|
  config.on(:startup) { Events::Schedule.load! }
end
