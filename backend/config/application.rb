require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks ci generators rubocop])

    # packs-rails añade app/* de cada pack a las rutas de carga, pero no db/migrate (M0.03):
    # las migraciones de cada pack se registran aquí para que `db:migrate` las encuentre.
    Packs.all.reject(&:is_gem?).each do |pack|
      paths["db/migrate"] << pack.relative_path.join("db/migrate").to_s
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Español de Nicaragua por defecto (rails-i18n trae es-NI); `en` solo como idioma de respaldo/técnico.
    config.i18n.available_locales = [ :"es-NI", :en ]
    config.i18n.default_locale = :"es-NI"

    # Todo se guarda y se procesa en UTC. La zona de referencia de negocio es la de la SUCURSAL
    # (branches.time_zone), nunca la del servidor (docs/architecture/09-data-conventions.md).
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Convenciones de base de datos (M0.04, docs/architecture/09-data-conventions.md):
    # PK uuid (default uuidv7() de PostgreSQL 18) y structure.sql en lugar de schema.rb, porque
    # las políticas RLS, las exclusion constraints y las extensiones no caben en schema.rb.
    config.active_record.schema_format = :sql
    config.generators { |g| g.orm :active_record, primary_key_type: :uuid }
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Los jobs van en Sidekiq (ADR-0009); Solid Queue no se usa.
    config.active_job.queue_adapter = :sidekiq

    # Sin variantes de imagen todavía: evita el aviso de `image_processing` en cada arranque.
    # Se reactiva (gema + :vips) cuando haya un hito que procese imágenes.
    config.active_storage.variant_processor = :disabled
  end
end
