# sidekiq-cron (M0.10): el relay corre cada 5 s, así que el poll del scheduler (30 s por defecto) debe ser menor.
Sidekiq::Cron.configure { |cron| cron.cron_poll_interval = 1 }

# Los jobs programados se registran cuando arranca el proceso de Sidekiq (no en el web ni en consola). Events::Schedule se
# resuelve en ese momento y no durante la inicialización (las clases recargables no se autocargan en initializers).
Sidekiq.configure_server do |config|
  config.on(:startup) { Events::Schedule.load! }
end
