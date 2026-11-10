# The constant is resolved on each notification, so it survives development reloads.
ActiveSupport::Notifications.subscribe("outbox_lag.events") { |*, payload| Events::OutboxLagAlert.call(payload) }
