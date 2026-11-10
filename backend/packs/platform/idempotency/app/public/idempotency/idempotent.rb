module Idempotency
  # Controller concern: makes the given actions idempotent.
  #
  #   class AppointmentsController < Api::BaseController
  #     include Idempotency::Idempotent
  #     idempotent :create, required: true
  #   end
  #
  # With the `Idempotency-Key` header:
  #   - first time: runs the action and, if it answers 2xx, stores the response for 24 hours;
  #   - same key and same method, path and body: does NOT run the action and replays the stored response
  #     (with `Idempotency-Replayed: true`);
  #   - same key and another method, path or body: 409 `idempotency.key_reused`.
  # The key is unique per organization and principal. A non-2xx response (or an exception) does not consume the key.
  # `required: true` demands the header (400 `idempotency.key_required`); without it and without `required`, the action
  # runs normally.
  #
  # Requirements: the tenancy context already open when the filter runs (declare `idempotent` AFTER the filter that
  # opens it, e.g. the Tenancy.with_context around_action) and, if the action is authenticated, Current.principal. Two
  # simultaneous requests race on the unique index: the second waits for the first to finish.
  module Idempotent
    extend ActiveSupport::Concern

    class_methods do
      def idempotent(*actions, required: false)
        around_action(only: actions) { |controller, action| controller.send(:process_idempotently, required, action) }
      end
    end

    private

    def process_idempotently(required, action)
      replay = Processor.call(request:, response:, required:, &action)
      render_replay(replay) if replay
    end

    def render_replay(replay)
      response.set_header("Idempotency-Replayed", "true")
      replay.headers.each { |name, value| response.set_header(name, value) }
      render body: replay.body, status: replay.status, content_type: replay.content_type
    end
  end
end
