namespace :sentry do
  desc "Envía un error y un job fallido de prueba a Sentry, con el tenant dado (requiere SENTRY_DSN). Uso: sentry:test[ORGANIZATION_ID]"
  task :test, [ :organization_id ] => :environment do |_task, args|
    organization_id = args[:organization_id].presence || Tenancy::Organization.order(:created_at).pick(:id)
    abort "sentry:test: no hay organizaciones; pasa un ID: sentry:test[<organization_id>]" unless organization_id

    case Observability::SentryCheck.run(organization_id:)
    when :disabled then abort "sentry:test: Sentry está desactivado (falta SENTRY_DSN o el entorno es test): no se envió nada"
    else
      Sentry.flush
      puts "Enviado el error de prueba (organization_id=#{organization_id}) y encolado Observability::SentryTestJob: " \
           "el worker lo ejecutará y fallará. Búscalos en Sentry por el tag organization_id."
    end
  end
end
