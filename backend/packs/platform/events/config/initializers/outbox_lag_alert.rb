# Alerta del lag del outbox (M0.13). La constante se resuelve en cada notificación: sobrevive a las recargas de desarrollo.
ActiveSupport::Notifications.subscribe("outbox_lag.events") { |*, payload| Events::OutboxLagAlert.call(payload) }
