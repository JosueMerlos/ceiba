# Flipper persisted in the database (flipper-active_record); the actor is the organization (Modules::FlagActor).
# With no flags defined, preloading them on EVERY request (even /api/health) would make Flipper's Memoizer read the database
# for nothing. Enable it once flags exist, and then for a list of routes, not globally.
Rails.application.config.flipper.preload = false

Rails.application.config.to_prepare do
  require "flipper/adapters/active_record"
  Flipper.configure { |config| config.adapter { Flipper::Adapters::ActiveRecord.new } }
  # The per-thread instance is memoized with the previous config (the railtie's in-memory adapter), so discard it.
  Flipper.instance = nil
end
