# Los jobs programados se registran cuando arranca el proceso de Sidekiq (no en el web ni en consola).
Sidekiq.configure_server do |config|
  config.on(:startup) { Idempotency::Schedule.load! }
end
