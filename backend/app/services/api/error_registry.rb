module Api
  # Registro de errores de dominio -> respuesta problem+json (docs/architecture/07-api-contract.md).
  #
  # Cada pack registra las excepciones que su dominio lanza y que el cliente debe poder distinguir, una vez, en un
  # initializer (dentro de `to_prepare`, para sobrevivir a la recarga de código):
  #
  #   Api::ErrorRegistry.register(Tenancy::InconsistentContext, status: :not_found, code: "tenancy.inconsistent_context")
  #
  # `status`, `code`, `title`, `detail` y `errors` aceptan un valor fijo o un callable que recibe la excepción. Qué se
  # expone es decisión explícita del registro: el mensaje de la excepción NO sale nunca por defecto (puede contener
  # SQL, rutas o nombres internos). Una excepción sin registrar es un bug y se responde 500 genérico.
  #
  # `code` es estable y único: el frontend lo traduce con i18n, así que dos clases no pueden compartirlo.
  module ErrorRegistry
    Entry = Struct.new(:status, :code, :title, :detail, :errors, keyword_init: true)

    # Lo ya resuelto contra una excepción concreta: valores finales, sin callables.
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

      # Busca por la clase más específica de la jerarquía de la excepción; nil si ninguna está registrada.
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
