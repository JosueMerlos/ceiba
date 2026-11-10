# Must be initialized in an initializer: sentry-rails registers its Rails.error subscriber at the end of boot, reading
# this configuration.
require Rails.root.join("config/middleware/sentry_setup").to_s

SentrySetup.init
