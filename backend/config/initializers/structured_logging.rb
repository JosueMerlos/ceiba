# Logs estructurados (M0.13, docs/architecture/10-infrastructure.md §Observabilidad).
#
# Decisión: lograge (una línea por request, con duración y status) + un formateador JSON propio, en lugar de
# rails_semantic_logger. Semantic Logger sustituye todo el logger de Rails y trae su propio hilo de escritura; aquí solo
# hace falta una línea por request y por job con campos fijos, y el resto de los logs (SQL de desarrollo, avisos) se queda
# como está pero en JSON. Menos piezas, menos superficie, versión fijada en el Gemfile.
#
# Campos de cada request: method, path (SIN query string), format, controller, action, status, duration (ms), view, db,
# allocations, request_id, remote_ip, organization_id, company_id, branch_id, principal_type, principal_id.
# Los parámetros NO se registran (ni siquiera filtrados): el filtro es una red de seguridad, no una autorización.
Rails.application.configure do
  config.lograge.enabled = true
  # El formateador del logger (Observability::JsonLogFormatter) serializa el Hash; así no se codifica dos veces.
  config.lograge.formatter = ->(data) { data }

  # La API hereda de ActionController::API, no de Base (el valor por defecto de lograge).
  config.lograge.base_controller_class = "ActionController::API"

  config.lograge.custom_payload_method = lambda do |controller|
    Observability::LogFields.current.merge(Observability::LogFields.request(controller.request))
  end

  # Las sondas de infraestructura se llaman cada pocos segundos: su línea solo es ruido.
  silenced_paths = %w[/api/health /api/ready].freeze
  config.lograge.ignore_custom = ->(event) { silenced_paths.include?(event.payload[:path].to_s.split("?").first) }
end

# Sin códigos de color ANSI: romperían el JSON de cada línea (el SQL de desarrollo los lleva).
ActiveSupport::LogSubscriber.colorize_logging = false

# Las constantes de app/ no se pueden usar al cargar un initializer (Zeitwerk aún no está listo): van en to_prepare, que
# vuelve a correr tras cada recarga de código en desarrollo.
Rails.application.config.to_prepare do
  # Una línea JSON también para el resto de los mensajes (production usa STDOUT; antes llevaba el prefijo [request_id], que
  # rompe el JSON: el request_id ya va como campo).
  Rails.logger.formatter = Observability::JsonLogFormatter.new

  Tenancy.singleton_class.prepend(Observability::TenancyHook) unless Tenancy.singleton_class.include?(Observability::TenancyHook)
end
