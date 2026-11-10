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
    config.autoload_lib(ignore: %w[assets tasks ci generators rubocop openapi])

    # packs-rails adds each pack's app/* to the load paths but not db/migrate, so register them for `db:migrate`.
    Packs.all.reject(&:is_gem?).each do |pack|
      paths["db/migrate"] << pack.relative_path.join("db/migrate").to_s
    end

    # config.factory_bot only exists in development and test, where factory_bot_rails is loaded.
    if config.respond_to?(:factory_bot)
      config.factory_bot.definition_file_paths += Dir[Rails.root.join("packs/*/*/spec/factories").to_s]
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Nicaraguan Spanish by default (rails-i18n ships es-NI); `en` is only a fallback/technical locale.
    config.i18n.available_locales = [ :"es-NI", :en ]
    config.i18n.default_locale = :"es-NI"

    # Everything is stored and processed in UTC. The business reference zone is the BRANCH's (branches.time_zone),
    # never the server's.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # structure.sql instead of schema.rb: RLS policies, exclusion constraints and extensions do not fit in schema.rb.
    # Primary keys are uuid (uuidv7() default in PostgreSQL 18).
    config.active_record.schema_format = :sql
    config.generators { |g| g.orm :active_record, primary_key_type: :uuid }
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Errors raised before a controller (unknown route, malformed JSON) also render as problem+json under /api.
    config.exceptions_app = ->(env) { Api::ExceptionsApp.new.call(env) } # autoloaded constant: resolved per request

    # Jobs run on Sidekiq; Solid Queue is not used.
    config.active_job.queue_adapter = :sidekiq

    # No image variants yet: avoids the `image_processing` warning on every boot. Re-enable (gem + :vips) when images are processed.
    config.active_storage.variant_processor = :disabled
  end
end
