module Events
  # Subscriber registry. Lives in the application config and NOT in a class ivar: in development classes reload and
  # would lose the registrations (same as the Tenancy::ProvisionOrganization hooks). Registering the same (event,
  # subscriber) again replaces it, so `config.to_prepare { Events.subscribe(...) }` is idempotent even on every reload.
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

      # Replaces the whole registry (tests use it to isolate themselves).
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
