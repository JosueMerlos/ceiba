module Api
  # Registry mapping domain errors to problem+json responses.
  #
  # Each pack registers, once, the exceptions its domain raises that the client must tell apart, in an initializer
  # (inside `to_prepare`, to survive code reloading):
  #
  #   Api::ErrorRegistry.register(Tenancy::InconsistentContext, status: :not_found, code: "tenancy.inconsistent_context")
  #
  # `status`, `code`, `title`, `detail` and `errors` take a fixed value or a callable that receives the exception. What
  # is exposed is an explicit registry decision: the exception message is NEVER exposed by default (it may contain SQL,
  # paths or internal names). An unregistered exception is a bug and answers a generic 500.
  #
  # `code` is stable and unique: the frontend translates it with i18n, so two classes cannot share one.
  module ErrorRegistry
    Entry = Struct.new(:status, :code, :title, :detail, :errors, keyword_init: true)

    # What is already resolved for a concrete exception: final values, no callables.
    Resolved = Struct.new(:status, :code, :title, :detail, :errors, keyword_init: true)

    @entries = {}

    class << self
      def register(error_class, status:, code:, title: nil, detail: nil, errors: nil)
        name = error_class.name || error_class.object_id.to_s
        taken = @entries.find { |other, entry| other != name && entry.code == code }
        raise ArgumentError, "el code #{code.inspect} ya está registrado para #{taken.first}" if taken

        @entries[name] = Entry.new(status:, code:, title:, detail:, errors:)
      end

      def unregister(error_class)
        @entries.delete(error_class.name || error_class.object_id.to_s)
      end

      # Looks up the most specific class in the exception's hierarchy; nil if none is registered.
      def resolve(exception)
        exception.class.ancestors.each do |ancestor|
          entry = @entries[ancestor.name || ancestor.object_id.to_s]
          return resolved(entry, exception) if entry
        end
        nil
      end

      private

      def resolved(entry, exception)
        status = value_of(entry.status, exception)
        Resolved.new(
          status: status.is_a?(Integer) ? status : Rack::Utils.status_code(status),
          code: value_of(entry.code, exception),
          title: value_of(entry.title, exception),
          detail: value_of(entry.detail, exception),
          errors: value_of(entry.errors, exception)
        )
      end

      def value_of(value, exception) = value.respond_to?(:call) ? value.call(exception) : value
    end
  end
end
