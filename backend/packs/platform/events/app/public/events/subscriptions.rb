module Events
  # Registro de suscriptores. Vive en la configuración de la aplicación y NO en un ivar de clase: en desarrollo las
  # clases se recargan y perderían los registros (mismo criterio que los hooks de Tenancy::ProvisionOrganization).
  # Registrar de nuevo el mismo (evento, suscriptor) lo reemplaza, así `config.to_prepare { Events.subscribe(...) }`
  # es idempotente aunque corra en cada recarga.
  module Subscriptions
    QUEUES = %w[critical default notifications low].freeze
    DEFAULT_QUEUE = "critical".freeze
    STORE = Rails.application.config.x.events

    class << self
      def register(event_name:, subscriber:, handler:, queue: DEFAULT_QUEUE)
        validate!(event_name, subscriber, handler, queue)
        subscription = Subscription.new(event_name: event_name.to_s, subscriber: subscriber.to_s, handler:, queue: queue.to_s)
        update do |all|
          index = all.index { |entry| entry.event_name == subscription.event_name && entry.subscriber == subscription.subscriber }
          index ? all.dup.tap { |copy| copy[index] = subscription } : all + [ subscription ]
        end
        subscription
      end

      def all = STORE.subscriptions || []

      def for_event(event_name) = all.select { |subscription| subscription.event_name == event_name.to_s }

      def find(event_name, subscriber)
        all.find { |subscription| subscription.event_name == event_name.to_s && subscription.subscriber == subscriber.to_s }
      end

      # Sustituye todo el registro (lo usan las pruebas para aislarse).
      def replace(subscriptions) = update { subscriptions }

      private

      def update
        lock.synchronize { STORE.subscriptions = yield(all).freeze }
      end

      def lock = STORE.subscriptions_lock ||= Mutex.new

      def validate!(event_name, subscriber, handler, queue)
        raise ArgumentError, "Nombre de evento inválido: #{event_name.inspect}" unless event_name.to_s.match?(OutboxEvent::NAME_FORMAT)
        raise ArgumentError, "El suscriptor necesita un nombre (as:)" if subscriber.to_s.strip.empty?
        raise ArgumentError, "La cola #{queue.inspect} no existe (colas: #{QUEUES.join(', ')})" unless QUEUES.include?(queue.to_s)
        raise ArgumentError, "El suscriptor requiere un bloque o un handler que responda a call" unless handler.respond_to?(:call)
      end
    end
  end
end
